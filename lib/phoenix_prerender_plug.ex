defmodule PhoenixPrerender.Plug do
  @moduledoc """
  Serves prerendered static HTML files when available.

  When a request matches a prerendered page, the plug serves the
  static file directly with appropriate headers. Otherwise, the
  request passes through to the Phoenix application.

  ## Usage

  Add to your endpoint before the router:

      plug PhoenixPrerender.Plug

  Or with options:

      plug PhoenixPrerender.Plug,
        output_path: "priv/static/prerendered",
        url_style: :dir_index,
        cache_control: "public, max-age=300"

  ## Configuration

  The plug respects the global `:enabled` configuration. When disabled,
  all requests pass through without checking for prerendered files.
  """

  @behaviour Plug

  @impl true
  def init(opts) do
    %{
      output_path: Keyword.get(opts, :output_path),
      url_style: Keyword.get(opts, :url_style),
      cache_control: Keyword.get(opts, :cache_control),
      enabled: Keyword.get(opts, :enabled)
    }
  end

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

    unless PhoenixPrerender.Path.safe?(path) do
      conn
    else
      output_path = opts.output_path || PhoenixPrerender.output_path()
      url_style = opts.url_style || PhoenixPrerender.url_style()
      cache_control = opts.cache_control || PhoenixPrerender.cache_control()

      file_path = PhoenixPrerender.Path.full_output_path(path, output_path, url_style)

      if File.exists?(file_path) do
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
      else
        conn
      end
    end
  end
end
