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
  """
  @impl true
  def init(opts) do
    %{
      output_path: Keyword.get(opts, :output_path),
      url_style: Keyword.get(opts, :url_style),
      cache_control: Keyword.get(opts, :cache_control),
      enabled: Keyword.get(opts, :enabled),
      endpoint: Keyword.get(opts, :endpoint),
      strict_paths: Keyword.get(opts, :strict_paths)
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

    if strict_paths?(opts) and not path_in_manifest?(path, output_path) do
      conn
    else
      # Try cache first, then disk
      case try_cache(path) do
        {:ok, html, metadata} ->
          maybe_trigger_isr_from_cache(path, metadata, endpoint)
          send_prerendered_body(conn, html, path, cache_control, :cache)

        :miss ->
          try_disk(conn, path, output_path, url_style, cache_control, endpoint)
      end
    end
  end

  # -- Strict paths (manifest check) ----------------------------------------

  defp path_in_manifest?(path, output_path) do
    case PhoenixPrerender.Manifest.read(output_path) do
      {:ok, manifest} -> PhoenixPrerender.Manifest.lookup(manifest, path) != nil
      {:error, _} -> false
    end
  end

  # -- Cache layer ----------------------------------------------------------

  defp try_cache(path) do
    PhoenixPrerender.PageCache.get(path)
  rescue
    # PageCache not started (ETS table doesn't exist)
    ArgumentError -> :miss
  end

  defp maybe_trigger_isr_from_cache(path, metadata, endpoint) do
    if isr_enabled?() and endpoint do
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

  defp try_disk(conn, path, output_path, url_style, cache_control, endpoint) do
    file_path = PhoenixPrerender.Path.full_output_path(path, output_path, url_style)

    if File.exists?(file_path) do
      maybe_trigger_isr_from_disk(path, file_path, endpoint)
      send_prerendered_file(conn, file_path, path, cache_control)
    else
      conn
    end
  end

  defp maybe_trigger_isr_from_disk(path, file_path, endpoint) do
    if isr_enabled?() and endpoint do
      if PhoenixPrerender.Regenerator.file_stale?(file_path) do
        PhoenixPrerender.Regenerator.maybe_regenerate(path, endpoint)
      end
    end
  end

  # -- Response helpers -----------------------------------------------------

  defp send_prerendered_file(conn, file_path, path, cache_control) do
    start_time = System.monotonic_time()

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.put_resp_header("cache-control", cache_control)
    |> Plug.Conn.put_resp_header("x-prerendered", "true")
    |> Plug.Conn.send_file(200, file_path)
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
end
