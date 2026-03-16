defmodule PhoenixPrerender.Route do
  @moduledoc """
  Discovers routes marked for prerendering from a Phoenix router.

  Routes are identified by checking the `private` metadata on each route
  for the configured key-value pair (default: `prerender: true`).
  """

  @doc """
  Returns all routes marked for prerendering from the given router.

  Uses `Phoenix.Router.routes/1` for route discovery and filters
  by the configured private key and value.

  ## Options

    * `:private_key` - the private metadata key to match (default: configured value)
    * `:private_value` - the private metadata value to match (default: configured value)

  ## Examples

      PhoenixPrerender.Route.discover(MyAppWeb.Router)
      [%{path: "/about", verb: :get, plug: PageController, plug_opts: :about}, ...]
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

  defp match_private?(%{metadata: metadata}, key, value) when is_map(metadata) do
    Map.get(metadata, key) == value
  end

  defp match_private?(_, _key, _value), do: false

  defp normalize_route(route) do
    %{
      path: route.path,
      verb: route.verb,
      plug: route.plug,
      plug_opts: route.plug_opts,
      metadata: Map.get(route, :metadata, %{})
    }
  end

  @doc """
  Returns only the paths from discovered routes.

  ## Examples

      PhoenixPrerender.Route.paths(MyAppWeb.Router)
      ["/about", "/docs/terms"]
  """
  @spec paths(module(), keyword()) :: [String.t()]
  def paths(router, opts \\ []) do
    router
    |> discover(opts)
    |> Enum.map(& &1.path)
  end
end
