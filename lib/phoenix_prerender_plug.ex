defmodule PhoenixPrerender.Plug do
  @moduledoc """
  Plug that serves prerendered static HTML files when available.

  When a request matches a prerendered page on disk, this plug serves
  the file directly with appropriate HTTP headers and halts the
  connection. Otherwise, the request passes through to the rest of the
  Phoenix pipeline (router, controllers, LiveViews).

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

  ## How It Works

  For each incoming request, the plug:

    1. Checks if prerendering is enabled (skips if disabled)
    2. Normalizes the request path (strips trailing slashes, query strings)
    3. Validates the path is safe (rejects directory traversal)
    4. Computes the expected file path using the configured URL style
    5. If the file exists on disk, serves it with `send_file/5` and halts
    6. If not, passes the connection through unchanged

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
        enabled: true

  ## Telemetry

  Emits `[:phoenix_prerender, :serve]` when a page is served with:

    * Measurements: `%{duration: native_time}`
    * Metadata: `%{path: String.t(), source: :disk}`
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
  """
  @impl true
  def init(opts) do
    %{
      output_path: Keyword.get(opts, :output_path),
      url_style: Keyword.get(opts, :url_style),
      cache_control: Keyword.get(opts, :cache_control),
      enabled: Keyword.get(opts, :enabled)
    }
  end

  @doc """
  Serves a prerendered file if one exists for the request path.

  When the plug is disabled or no matching file exists, the connection
  is returned unchanged. When a file is served, the connection is
  halted after sending.
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

  defp serve_prerendered(conn, opts) do
    path = PhoenixPrerender.Path.normalize(conn.request_path)

    if PhoenixPrerender.Path.safe?(path) do
      maybe_serve_file(conn, path, opts)
    else
      conn
    end
  end

  defp maybe_serve_file(conn, path, opts) do
    output_path = opts.output_path || PhoenixPrerender.output_path()
    url_style = opts.url_style || PhoenixPrerender.url_style()
    cache_control = opts.cache_control || PhoenixPrerender.cache_control()

    file_path = PhoenixPrerender.Path.full_output_path(path, output_path, url_style)

    if File.exists?(file_path) do
      send_prerendered(conn, file_path, path, cache_control)
    else
      conn
    end
  end

  defp send_prerendered(conn, file_path, path, cache_control) do
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
end
