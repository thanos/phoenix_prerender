defmodule PhoenixPrerender.Plug do
  @moduledoc """
  Plug that serves prerendered HTML pages with optional ISR support.

  When a request matches a prerendered page, this plug serves it directly
  with appropriate HTTP headers and halts the connection. Otherwise, the
  request passes through to the rest of the Phoenix pipeline.

  ## Serving Order

  The plug checks for content in this order:

    1. **Memory cache** -- if `PhoenixPrerender.PageCache` is running,
       check ETS for the requested path
    2. **Disk** -- check for a prerendered file at the expected path
    3. **Pass-through** -- let the request continue to the Phoenix router

  ## Strict Paths

  When `strict_paths` is enabled (the default), the plug only serves
  pages whose paths appear in the `manifest.json` file. This prevents
  serving arbitrary files that happen to exist in the output directory.

  When disabled, any file found at the expected path is served.

      config :phoenix_prerender, strict_paths: true

  The manifest is loaded once during `init/1` and cached in the plug
  opts. To pick up new pages after regeneration, the plug re-reads
  the manifest when a path is not found in the cached version.

  ## Incremental Static Regeneration (ISR)

  When ISR is enabled (`config :phoenix_prerender, isr: true`), the plug
  implements the **stale-while-revalidate** pattern:

    1. Serve the existing content immediately (stale is OK)
    2. If the content is older than `revalidate` seconds, trigger a
       background regeneration via `PhoenixPrerender.Regenerator`
    3. The next request gets the fresh content

  This means users always get an instant response — they never wait for
  a page to re-render.

  ## Setup

  Add the plug to your endpoint module, before the router:

      defmodule MyAppWeb.Endpoint do
        use Phoenix.Endpoint, otp_app: :my_app

        plug Plug.Static, ...

        # Serve prerendered pages
        plug PhoenixPrerender.Plug

        plug MyAppWeb.Router
      end

  Then enable it in your production config:

      # config/prod.exs
      config :phoenix_prerender, enabled: true

  For ISR, also pass the endpoint and enable ISR:

      plug PhoenixPrerender.Plug, endpoint: MyAppWeb.Endpoint

      config :phoenix_prerender,
        enabled: true,
        isr: true,
        revalidate: 300

  ## Response Headers

  When serving a prerendered page, the plug sets:

    * `content-type: text/html`
    * `cache-control:` value from configuration (default: `"public, max-age=300"`)
    * `x-prerendered: true` (useful for debugging and monitoring)

  ## Inline Options

  Options can be passed directly to the plug to override global config:

      plug PhoenixPrerender.Plug,
        output_path: "priv/static/prerendered",
        url_style: :dir_index,
        cache_control: "public, max-age=3600",
        endpoint: MyAppWeb.Endpoint,
        strict_paths: false,
        enabled: true

  > **Important:** The `output_path` and `url_style` must match what was
  > used when generating files with `mix phx.prerender`. If the task wrote
  > files with `--style file` but the plug defaults to `:dir_index`, it
  > will look for `about/index.html` when the file is actually `about.html`.
  > The safest approach is to set both values in application config so the
  > task and plug stay in sync automatically.

  ## Telemetry

  Emits `[:phoenix_prerender, :serve]` when a page is served with:

    * Measurements: `%{duration: native_time}`
    * Metadata: `%{path: String.t(), source: :disk | :cache}`
  """

  @behaviour Plug

  @doc """
  Initializes the plug with the given options.

  ## Options

    * `:output_path` -- directory containing prerendered files
      (default: from application config)
    * `:url_style` -- `:dir_index` or `:file`
      (default: from application config)
    * `:cache_control` -- `Cache-Control` header value
      (default: from application config)
    * `:enabled` -- whether the plug is active
      (default: from application config)
    * `:endpoint` -- the Phoenix endpoint module, required for ISR
      regeneration (default: `nil`)
    * `:strict_paths` -- only serve paths listed in `manifest.json`
      (default: from application config, defaults to `true`)
    * `:bots_only` -- only serve prerendered pages to search engine
      crawlers. Regular browsers are passed through to the live app.
      Essential for LiveView routes where prerendered HTML contains
      stale session data. (default: from application config, defaults
      to `false`)
  """
  @impl true
  def init(opts) do
    session_options = Keyword.get(opts, :session_options)

    %{
      output_path: Keyword.get(opts, :output_path),
      url_style: Keyword.get(opts, :url_style),
      cache_control: Keyword.get(opts, :cache_control),
      enabled: Keyword.get(opts, :enabled),
      endpoint: Keyword.get(opts, :endpoint),
      strict_paths: Keyword.get(opts, :strict_paths),
      bots_only: Keyword.get(opts, :bots_only),
      session_init: session_options && Plug.Session.init(session_options),
      csrf_init: session_options && Plug.CSRFProtection.init([])
    }
  end

  @doc """
  Serves a prerendered page if one exists for the request path.

  When the plug is disabled or no matching content exists, the connection
  is returned unchanged. When a page is served, the connection is halted
  after sending.

  When ISR is enabled, stale content is served immediately while a
  background task regenerates the page.
  """
  # Common search engine crawler user-agent patterns (case-insensitive).
  @bot_patterns ~w(
    googlebot bingbot yandexbot duckduckbot baiduspider
    slurp sogou facebookexternalhit twitterbot linkedinbot
    whatsapp telegrambot applebot amazonbot bytespider
    gptbot claudebot petalbot semrushbot ahrefsbot
    mj12bot dotbot rogerbot screaming\ frog
  )

  @impl true
  def call(conn, opts) do
    if enabled?(opts) do
      serve_prerendered(conn, opts)
    else
      conn
    end
  end

  defp enabled?(%{enabled: nil}), do: PhoenixPrerender.enabled?()
  defp enabled?(%{enabled: value}), do: value

  defp strict_paths?(%{strict_paths: nil}), do: PhoenixPrerender.strict_paths()
  defp strict_paths?(%{strict_paths: value}), do: value

  defp bots_only?(%{bots_only: nil}), do: PhoenixPrerender.bots_only()
  defp bots_only?(%{bots_only: value}), do: value

  defp serve_to_client?(conn, opts, entry) do
    cond do
      bots_only?(opts) -> bot_request?(conn)
      bots_only_route?(entry) -> bot_request?(conn)
      true -> true
    end
  end

  defp bots_only_route?(%{"prerender_mode" => "bots_only"}), do: true
  defp bots_only_route?(_), do: false

  defp bot_request?(conn) do
    conn
    |> Plug.Conn.get_req_header("user-agent")
    |> Enum.any?(fn ua ->
      ua_down = String.downcase(ua)
      Enum.any?(@bot_patterns, &String.contains?(ua_down, &1))
    end)
  end

  defp serve_prerendered(conn, opts) do
    path = PhoenixPrerender.Path.normalize(conn.request_path)

    if PhoenixPrerender.Path.safe?(path) do
      resolve_and_serve(conn, path, opts)
    else
      conn
    end
  end

  defp resolve_and_serve(conn, path, opts) do
    output_path = opts.output_path || PhoenixPrerender.output_path()
    url_style = opts.url_style || PhoenixPrerender.url_style()
    cache_control = opts.cache_control || PhoenixPrerender.cache_control()
    endpoint = opts.endpoint

    maybe_invalidate_cache(output_path)

    entry = if strict_paths?(opts), do: manifest_entry(path, output_path), else: :no_manifest

    if should_serve?(conn, opts, entry) do
      do_serve(conn, path, output_path, url_style, cache_control, endpoint, entry, opts)
    else
      conn
    end
  end

  defp should_serve?(conn, opts, entry) do
    not (strict_paths?(opts) and entry == nil) and serve_to_client?(conn, opts, entry)
  end

  defp do_serve(conn, path, output_path, url_style, cache_control, endpoint, entry, opts) do
    if always_route?(entry) and opts.session_init != nil do
      serve_with_fresh_session(conn, path, output_path, url_style, cache_control, endpoint, entry, opts)
    else
      try_cache_then_disk(conn, path, output_path, url_style, cache_control, endpoint, entry)
    end
  end

  defp try_cache_then_disk(conn, path, output_path, url_style, cache_control, endpoint, entry) do
    case try_cache(path) do
      {:ok, html, metadata} ->
        maybe_trigger_isr_from_cache(path, metadata, endpoint, entry)
        send_prerendered_body(conn, html, path, cache_control, :cache)

      :miss ->
        try_disk(conn, path, output_path, url_style, cache_control, endpoint, entry)
    end
  end

  # Checks if the generation stamp has changed since the last request.
  # If it has, clears the ETS page cache so fresh files are read from disk.
  # Uses :persistent_term to store the last-seen stamp across all processes.
  defp maybe_invalidate_cache(output_path) do
    current = PhoenixPrerender.GenerationStamp.read(output_path)

    if current do
      last_seen = :persistent_term.get({__MODULE__, :generation_stamp}, nil)

      if last_seen != nil and last_seen != current do
        PhoenixPrerender.PageCache.clear()
      end

      if last_seen != current do
        :persistent_term.put({__MODULE__, :generation_stamp}, current)
      end
    end
  rescue
    ArgumentError -> :ok
  catch
    :exit, _ -> :ok
  end

  # -- Strict paths (manifest check) ----------------------------------------

  defp manifest_entry(path, output_path) do
    case PhoenixPrerender.Manifest.read(output_path) do
      {:ok, manifest} -> PhoenixPrerender.Manifest.lookup(manifest, path)
      {:error, _} -> nil
    end
  end

  # -- Cache layer ----------------------------------------------------------

  defp try_cache(path) do
    PhoenixPrerender.PageCache.get(path)
  rescue
    # PageCache not started (ETS table doesn't exist)
    ArgumentError -> :miss
  end

  defp maybe_trigger_isr_from_cache(path, metadata, endpoint, entry) do
    if isr_for_route?(entry) and endpoint do
      revalidate = PhoenixPrerender.Regenerator.revalidate_interval()

      if cache_entry_stale?(metadata, revalidate) do
        PhoenixPrerender.Regenerator.maybe_regenerate(path, endpoint)
      end
    end
  end

  defp cache_entry_stale?(%{cached_at: cached_at}, revalidate_seconds) do
    age = System.monotonic_time() - cached_at
    age_seconds = System.convert_time_unit(age, :native, :second)
    age_seconds >= revalidate_seconds
  end

  defp cache_entry_stale?(_, _), do: true

  # -- Disk layer -----------------------------------------------------------

  defp try_disk(conn, path, output_path, url_style, cache_control, endpoint, entry) do
    file_path = PhoenixPrerender.Path.full_output_path(path, output_path, url_style)

    if File.exists?(file_path) do
      maybe_trigger_isr_from_disk(path, file_path, endpoint, entry)
      send_prerendered_file(conn, file_path, path, cache_control)
    else
      conn
    end
  end

  defp maybe_trigger_isr_from_disk(path, file_path, endpoint, entry) do
    if isr_for_route?(entry) and endpoint do
      if PhoenixPrerender.Regenerator.file_stale?(file_path) do
        PhoenixPrerender.Regenerator.maybe_regenerate(path, endpoint)
      end
    end
  end

  # -- Always-route CSRF swap -----------------------------------------------

  defp always_route?(%{"prerender_mode" => "always"}), do: true
  defp always_route?(_), do: false

  # For :always routes, establish a fresh session and CSRF token so that
  # LiveView's WebSocket connection can validate successfully. The
  # prerendered HTML is served with the stale CSRF meta tag replaced by
  # a fresh one, and the response includes a valid session cookie.
  defp serve_with_fresh_session(conn, path, output_path, url_style, cache_control, endpoint, entry, opts) do
    html =
      case try_cache(path) do
        {:ok, html, metadata} ->
          maybe_trigger_isr_from_cache(path, metadata, endpoint, entry)
          html

        :miss ->
          read_from_disk(path, output_path, url_style, endpoint, entry)
      end

    if html do
      conn = establish_session(conn, opts)
      fresh_token = Plug.CSRFProtection.get_csrf_token()
      html = replace_csrf_token(html, fresh_token)
      send_prerendered_body(conn, html, path, cache_control, :disk)
    else
      conn
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_from_disk(path, output_path, url_style, endpoint, entry) do
    file_path = PhoenixPrerender.Path.full_output_path(path, output_path, url_style)

    if File.exists?(file_path) do
      maybe_trigger_isr_from_disk(path, file_path, endpoint, entry)
      File.read!(file_path)
    else
      nil
    end
  end

  defp establish_session(conn, opts) do
    conn
    |> Plug.Session.call(opts.session_init)
    |> Plug.Conn.fetch_session()
    |> Plug.CSRFProtection.call(opts.csrf_init)
  end

  @csrf_meta_pattern ~r/<meta\s+name="csrf-token"\s+content="[^"]*"/
  defp replace_csrf_token(html, fresh_token) do
    Regex.replace(
      @csrf_meta_pattern,
      html,
      ~s(<meta name="csrf-token" content="#{fresh_token}")
    )
  end

  # -- Response helpers -----------------------------------------------------

  # sobelow_skip ["Traversal.SendFile"]
  defp send_prerendered_file(conn, file_path, path, cache_control) do
    case negotiate_encoding(conn, file_path) do
      :not_acceptable ->
        conn
        |> append_vary("accept-encoding")
        |> Plug.Conn.send_resp(406, "Not Acceptable")
        |> Plug.Conn.halt()

      {actual_file, encoding} ->
        do_send_prerendered_file(conn, actual_file, encoding, path, cache_control)
    end
  end

  # sobelow_skip ["Traversal.SendFile"]
  defp do_send_prerendered_file(conn, actual_file, encoding, path, cache_control) do
    start_time = System.monotonic_time()

    conn =
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.put_resp_header("cache-control", cache_control)
      |> Plug.Conn.put_resp_header("x-prerendered", "true")

    conn = append_vary(conn, "accept-encoding")

    conn =
      if encoding do
        Plug.Conn.put_resp_header(conn, "content-encoding", encoding)
      else
        conn
      end

    conn
    |> Plug.Conn.send_file(200, actual_file)
    |> tap(fn _ ->
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:phoenix_prerender, :serve],
        %{duration: duration},
        %{path: path, source: :disk}
      )
    end)
    |> Plug.Conn.halt()
  end

  # sobelow_skip ["XSS.SendResp"]
  defp send_prerendered_body(conn, html, path, cache_control, source) do
    start_time = System.monotonic_time()

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.put_resp_header("cache-control", cache_control)
    |> Plug.Conn.put_resp_header("x-prerendered", "true")
    |> Plug.Conn.send_resp(200, html)
    |> tap(fn _ ->
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:phoenix_prerender, :serve],
        %{duration: duration},
        %{path: path, source: source}
      )
    end)
    |> Plug.Conn.halt()
  end

  defp isr_enabled? do
    PhoenixPrerender.Regenerator.isr_enabled?()
  end

  # -- Encoding negotiation ---------------------------------------------------

  # Preference order: brotli first, then gzip.
  @encoding_candidates [
    {"br", ".br"},
    {"gzip", ".gz"}
  ]

  defp negotiate_encoding(conn, file_path) do
    accepted = parse_accept_encoding(conn)

    case Enum.find_value(@encoding_candidates, nil, fn {encoding, ext} ->
           find_compressed_variant(encoding, file_path <> ext, accepted)
         end) do
      {_path, _encoding} = match ->
        match

      nil ->
        if identity_rejected?(accepted) do
          :not_acceptable
        else
          {file_path, nil}
        end
    end
  end

  defp find_compressed_variant(encoding, compressed_path, accepted) do
    if encoding_accepted?(encoding, accepted) and File.exists?(compressed_path) do
      {compressed_path, encoding}
    end
  end

  defp encoding_accepted?(encoding, accepted) do
    case Map.fetch(accepted, encoding) do
      {:ok, q} when q > 0 -> true
      _ -> wildcard_accepted?(encoding, accepted)
    end
  end

  defp wildcard_accepted?(encoding, accepted) do
    case Map.fetch(accepted, "*") do
      {:ok, q} when q > 0 -> not Map.has_key?(accepted, encoding)
      _ -> false
    end
  end

  # Returns true when the client has explicitly rejected uncompressed responses.
  # This happens when identity;q=0 is sent, or *;q=0 is sent without an
  # explicit identity entry with q > 0.
  defp identity_rejected?(accepted) when map_size(accepted) == 0, do: false

  defp identity_rejected?(accepted) do
    case Map.fetch(accepted, "identity") do
      {:ok, q} -> q == 0.0
      :error -> wildcard_rejects_identity?(accepted)
    end
  end

  defp wildcard_rejects_identity?(accepted) do
    case Map.fetch(accepted, "*") do
      {:ok, q} -> q == 0.0
      :error -> false
    end
  end

  defp parse_accept_encoding(conn) do
    conn
    |> Plug.Conn.get_req_header("accept-encoding")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.reduce(%{}, fn part, acc ->
      case parse_encoding_part(part) do
        :skip -> acc
        {encoding, q} -> Map.update(acc, encoding, q, &max(&1, q))
      end
    end)
  end

  defp parse_encoding_part(part) do
    case String.split(part, ";") do
      [token] ->
        encoding = token |> String.trim() |> String.downcase()
        if encoding == "", do: :skip, else: {encoding, 1.0}

      [token | params] ->
        encoding = token |> String.trim() |> String.downcase()

        if encoding == "" do
          :skip
        else
          {encoding, extract_q_value(params)}
        end
    end
  end

  defp extract_q_value(params) do
    Enum.find_value(params, 1.0, fn param ->
      param = String.trim(param)

      case String.split(param, "=", parts: 2) do
        ["q", value] -> parse_q(value)
        _ -> nil
      end
    end)
  end

  defp parse_q(value) do
    case Float.parse(String.trim(value)) do
      {q, _} when q >= 0.0 and q <= 1.0 -> q
      _ -> 1.0
    end
  end

  # Appends a token to the Vary header, preserving any existing values
  # and deduplicating so the same token is not listed twice.
  defp append_vary(conn, token) do
    existing = Plug.Conn.get_resp_header(conn, "vary")

    tokens =
      existing
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.downcase/1)

    if token in tokens do
      conn
    else
      value =
        case existing do
          [] -> token
          _ -> Enum.join(existing, ", ") <> ", " <> token
        end

      Plug.Conn.put_resp_header(conn, "vary", value)
    end
  end
end
