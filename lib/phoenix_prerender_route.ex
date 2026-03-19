defmodule PhoenixPrerender.Route do
  @moduledoc """
  Discovers routes marked for prerendering from a Phoenix router.

  Route discovery uses `Phoenix.Router.routes/1` to enumerate all routes
  defined in a router module, then filters by checking each route's
  `metadata` map for the configured key-value pair (default:
  `prerender: true`).

  This approach uses `route.path` as the canonical source of truth,
  which means scope prefixes, nested scopes, and verified routes all
  work correctly without manual path reconstruction.

  ## Example

  Given this router:

      scope "/", MyAppWeb do
        pipe_through :browser

        get "/", PageController, :home
        get "/about", PageController, :about, metadata: %{prerender: true}

        scope "/docs" do
          get "/terms", PageController, :terms, metadata: %{prerender: true}
        end
      end

  Route discovery returns:

      PhoenixPrerender.Route.paths(MyAppWeb.Router)
      #=> ["/about", "/docs/terms"]

  The root `/` route is excluded because it lacks prerender metadata.
  """

  @doc """
  Returns all routes marked for prerendering from the given router.

  Each returned route is a map with the following keys:

    * `:path` -- the canonical URL path (e.g., `"/about"`)
    * `:verb` -- the HTTP method (e.g., `:get`)
    * `:plug` -- the controller or LiveView module
    * `:plug_opts` -- the action atom or LiveView options
    * `:metadata` -- the full metadata map from the route definition

  ## Options

    * `:private_key` -- the metadata key to match
      (default: `PhoenixPrerender.route_private_key/0`)
    * `:private_value` -- the metadata value to match
      (default: `PhoenixPrerender.route_private_value/0`)

  ## Examples

      routes = PhoenixPrerender.Route.discover(MyAppWeb.Router)
      #=> [%{path: "/about", verb: :get, plug: MyAppWeb.PageController, ...}, ...]

      # With custom metadata key
      PhoenixPrerender.Route.discover(MyAppWeb.Router,
        private_key: :static,
        private_value: true
      )
  """
  @spec discover(module(), keyword()) :: [map()]
  def discover(router, opts \\ []) do
    key = Keyword.get(opts, :private_key, PhoenixPrerender.route_private_key())
    value = Keyword.get(opts, :private_value, PhoenixPrerender.route_private_value())

    router
    |> Phoenix.Router.routes()
    |> Enum.filter(fn route ->
      match_private?(route, key, value)
    end)
    |> Enum.map(&normalize_route/1)
  end

  defp match_private?(%{metadata: metadata}, key, _value) when is_map(metadata) do
    val = Map.get(metadata, key)
    val != nil and val != false
  end

  defp match_private?(_, _key, _value), do: false

  defp normalize_route(route) do
    metadata = Map.get(route, :metadata, %{})

    %{
      path: route.path,
      verb: route.verb,
      plug: route.plug,
      plug_opts: route.plug_opts,
      metadata: metadata,
      prerender_mode: Map.get(metadata, :prerender, true),
      isr: Map.get(metadata, :isr, false)
    }
  end

  @doc """
  Returns only the URL paths from discovered prerender routes.

  This is a convenience function that extracts just the path strings
  from `discover/2`. Useful when you only need the list of paths
  for generation.

  ## Options

  Accepts the same options as `discover/2`.

  ## Examples

      PhoenixPrerender.Route.paths(MyAppWeb.Router)
      #=> ["/about", "/docs/terms"]
  """
  @spec paths(module(), keyword()) :: [String.t()]
  def paths(router, opts \\ []) do
    router
    |> discover(opts)
    |> Enum.map(& &1.path)
  end
end
