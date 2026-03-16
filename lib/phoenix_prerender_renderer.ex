defmodule PhoenixPrerender.Renderer do
  @moduledoc """
  Renders Phoenix routes through the full endpoint pipeline.

  Uses `Phoenix.ConnTest.build_conn/0` and `Phoenix.ConnTest.dispatch/5`
  to dispatch a GET request through the complete endpoint plug pipeline.
  This ensures that:

    * All endpoint plugs execute (session, CSRF, etc.)
    * Telemetry events fire
    * LiveView root layouts render
    * The HTML output matches what a real browser request would receive

  LiveView routes are rendered via their HTTP (non-WebSocket) path,
  producing static HTML that includes `data-phx-session` and
  `data-phx-static` attributes for client-side hydration.

  ## Example

      {:ok, html} = PhoenixPrerender.Renderer.render(MyAppWeb.Endpoint, "/about")
      # html contains the full HTML document as a string

  ## Telemetry

  Emits `[:phoenix_prerender, :render]` after each render with:

    * Measurements: `%{duration: native_time}`
    * Metadata: `%{path: "/about", status: 200}`
  """

  @doc """
  Renders the given path through the endpoint and returns the HTML body.

  Builds a connection with `accept: text/html` header and dispatches
  it through the given endpoint module. Only HTTP 200 responses are
  considered successful.

  ## Return Values

    * `{:ok, html}` -- the page rendered successfully
    * `{:error, {:unexpected_status, status, path}}` -- non-200 HTTP status
    * `{:error, {:render_error, message, path}}` -- exception during rendering

  ## Examples

      {:ok, html} = PhoenixPrerender.Renderer.render(MyAppWeb.Endpoint, "/about")
      String.contains?(html, "About")
      #=> true

      {:error, {:unexpected_status, 404, "/missing"}} =
        PhoenixPrerender.Renderer.render(MyAppWeb.Endpoint, "/missing")
  """
  @spec render(module(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def render(endpoint, path) do
    start_time = System.monotonic_time()

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "text/html")

    try do
      conn = Phoenix.ConnTest.dispatch(conn, endpoint, :get, path)

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:phoenix_prerender, :render],
        %{duration: duration},
        %{path: path, status: conn.status}
      )

      case conn.status do
        200 ->
          {:ok, conn.resp_body}

        status ->
          {:error, {:unexpected_status, status, path}}
      end
    rescue
      e ->
        {:error, {:render_error, Exception.message(e), path}}
    end
  end

  @doc """
  Renders the given path through the endpoint, raising on failure.

  Same as `render/2` but returns the HTML string directly or raises
  a `RuntimeError` with the failure details.

  ## Examples

      html = PhoenixPrerender.Renderer.render!(MyAppWeb.Endpoint, "/about")
      # Returns HTML string directly

      # Raises RuntimeError for missing pages:
      PhoenixPrerender.Renderer.render!(MyAppWeb.Endpoint, "/missing")
      #=> ** (RuntimeError) Failed to render /missing: {:unexpected_status, 404, "/missing"}
  """
  @spec render!(module(), String.t()) :: String.t()
  def render!(endpoint, path) do
    case render(endpoint, path) do
      {:ok, html} -> html
      {:error, reason} -> raise "Failed to render #{path}: #{inspect(reason)}"
    end
  end
end
