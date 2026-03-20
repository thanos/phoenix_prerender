defmodule PhoenixPrerender.Route do
  @moduledoc """
  Discovers routes marked for prerendering from a Phoenix router.

  Route discovery uses `Phoenix.Router.routes/1` to enumerate all routes
  defined in a router module, then filters by checking each route's
  `metadata` map for the configured key (default: `:prerender`).

  By default, any truthy value matches (`true`, `:bots_only`, `:always`,
  etc.). When a specific `:private_value` is passed, only routes with
  that exact value are returned.

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
    * `:private_value` -- when provided, only match routes with this
      exact metadata value. When omitted (or set to the default), any
      truthy value matches (`true`, `:bots_only`, `:always`, etc.).
      (default: `PhoenixPrerender.route_private_value/0`)

  ## Examples

      # Discovers all routes with any truthy :prerender value
      routes = PhoenixPrerender.Route.discover(MyAppWeb.Router)
      #=> [%{path: "/about", verb: :get, plug: MyAppWeb.PageController, ...}, ...]

      # Only routes with prerender: :bots_only
      PhoenixPrerender.Route.discover(MyAppWeb.Router,
        private_value: :bots_only
      )

      # Custom metadata key with exact value
      PhoenixPrerender.Route.discover(MyAppWeb.Router,
        private_key: :static,
        private_value: :seo
      )
  """
  @spec discover(module(), keyword()) :: [map()]
  def discover(router, opts \\ []) do
    key = Keyword.get(opts, :private_key, PhoenixPrerender.route_private_key())
    exact_value = Keyword.get(opts, :private_value)

    router
    |> Phoenix.Router.routes()
    |> Enum.filter(fn route ->
      match_private?(route, key, exact_value)
    end)
    |> Enum.map(&normalize_route/1)
  end

  # When no specific value is requested, match any truthy metadata value
  defp match_private?(%{metadata: metadata}, key, nil) when is_map(metadata) do
    val = Map.get(metadata, key)
    val != nil and val != false
  end

  # When a specific value is requested, do exact matching
  defp match_private?(%{metadata: metadata}, key, exact) when is_map(metadata) do
    Map.get(metadata, key) == exact
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
