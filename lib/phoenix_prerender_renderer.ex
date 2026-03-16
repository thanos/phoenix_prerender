defmodule PhoenixPrerender.Renderer do
  @moduledoc """
  Renders Phoenix routes through the full endpoint pipeline.

  Uses `Phoenix.ConnTest.dispatch/5` to ensure endpoint plugs execute,
  telemetry fires, LiveView root layout runs, and responses match
  production output.
  """

  @doc """
  Renders the given path through the endpoint and returns the HTML body.

  Dispatches a GET request through the full endpoint pipeline,
  including all plugs, telemetry, and layouts.

  Returns `{:ok, html}` on success or `{:error, reason}` on failure.

  ## Examples

      PhoenixPrerender.Renderer.render(MyAppWeb.Endpoint, "/about")
      {:ok, "<!DOCTYPE html>..."}
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
  Renders the given path and raises on failure.
  """
  @spec render!(module(), String.t()) :: String.t()
  def render!(endpoint, path) do
    case render(endpoint, path) do
      {:ok, html} -> html
      {:error, reason} -> raise "Failed to render #{path}: #{inspect(reason)}"
    end
  end
end
