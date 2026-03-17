defmodule PhoenixPrerender.StaticAsset do
  @moduledoc """
  Resolves asset paths to their digested counterparts via a Phoenix endpoint.

  During `mix phoenix.prerender`, the endpoint is started (the task calls
  `app.start`), so Phoenix's own `Endpoint.static_path/1` already works in
  templates. This module provides a standalone function for programmatic use
  and edge cases where you need to resolve digested asset paths outside of
  templates.

  ## How It Works

  Phoenix endpoints with a `cache_static_manifest` configuration maintain a
  mapping of undigested paths to their digested equivalents (e.g.,
  `/assets/app.css` to `/assets/app-ABC123.css`). This module delegates to
  the endpoint's `static_path/1` function to perform that resolution.

  When the endpoint is not started, or the manifest is not configured, the
  original path is returned unchanged as a graceful fallback.

  ## Examples

      # When endpoint has a static manifest configured
      PhoenixPrerender.StaticAsset.static_path(MyAppWeb.Endpoint, "/assets/app.css")
      #=> "/assets/app-ABC123.css"

      # When endpoint is not started or manifest is missing (dev mode)
      PhoenixPrerender.StaticAsset.static_path(MyAppWeb.Endpoint, "/assets/app.css")
      #=> "/assets/app.css"
  """

  @doc """
  Resolves an asset path to its digested counterpart via the endpoint.

  Calls `endpoint.static_path(asset_path)` to resolve the path. If the
  endpoint is not started, or the function is not available, the original
  `asset_path` is returned unchanged.

  ## Parameters

    * `endpoint` -- a Phoenix endpoint module
    * `asset_path` -- the undigested asset path (e.g., `"/assets/app.css"`)

  ## Examples

      iex> PhoenixPrerender.StaticAsset.static_path(PhoenixPrerenderWeb.Endpoint, "/assets/app.css")
      "/assets/app.css"
  """
  @spec static_path(module(), String.t()) :: String.t()
  def static_path(endpoint, asset_path) do
    endpoint.static_path(asset_path)
  rescue
    UndefinedFunctionError -> asset_path
    ArgumentError -> asset_path
  end
end
