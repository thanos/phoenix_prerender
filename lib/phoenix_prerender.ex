defmodule PhoenixPrerender do
  @moduledoc """
  Static prerendering and incremental regeneration for Phoenix applications.

  PhoenixPrerender enables build-time static generation, production static
  serving, and incremental static regeneration, similar to Next.js and
  SvelteKit, built natively for the BEAM.

  ## Configuration

      config :phoenix_prerender,
        enabled: false,
        output_path: "priv/static/prerendered",
        url_style: :dir_index,
        cache_control: "public, max-age=300",
        strict_paths: true,
        route_private_key: :prerender,
        route_private_value: true,
        concurrency: System.schedulers_online(),
        isr: false,
        revalidate: 300,
        strategy: :stale_while_revalidate

  ## Route Designation

  Routes are marked for prerendering via router metadata:

      get "/about", PageController, :about, metadata: %{prerender: true}
      live "/docs/terms", TermsLive, :index, metadata: %{prerender: true}

  Or using the `prerender` macro:

      import PhoenixPrerender

      prerender do
        get "/about", PageController, :about
        live "/docs/terms", TermsLive
      end

  ## Static Generation

      mix phoenix.prerender --router MyAppWeb.Router --endpoint MyAppWeb.Endpoint
  """

  @doc """
  Wraps route definitions and injects `metadata: %{prerender: true}`.

  ## Example

      import PhoenixPrerender

      prerender do
        get "/about", PageController, :about
        live "/docs/terms", TermsLive
      end
  """
  defmacro prerender(do: block) do
    inject_prerender_private(block)
  end

  defp inject_prerender_private({:__block__, meta, exprs}) do
    {:__block__, meta, Enum.map(exprs, &inject_single/1)}
  end

  defp inject_prerender_private(expr) do
    inject_single(expr)
  end

  defp inject_single({verb, meta, args}) when verb in [:get, :post, :put, :patch, :delete] do
    {verb, meta, append_private(args)}
  end

  defp inject_single({:live, meta, args}) do
    {:live, meta, append_private(args)}
  end

  defp inject_single(other), do: other

  @prerender_key Application.compile_env(:phoenix_prerender, :route_private_key, :prerender)
  @prerender_value Application.compile_env(:phoenix_prerender, :route_private_value, true)

  defp append_private(args) do
    key = @prerender_key
    value = @prerender_value
    metadata = Macro.escape(%{key => value})

    case List.last(args) do
      opts when is_list(opts) ->
        case Keyword.get(opts, :metadata) do
          {:%{}, _, _} = existing_map ->
            merged = quote do: Map.put(unquote(existing_map), unquote(key), unquote(value))
            new_opts = Keyword.put(opts, :metadata, merged)
            List.replace_at(args, -1, new_opts)

          _ ->
            new_opts = Keyword.put(opts, :metadata, metadata)
            List.replace_at(args, -1, new_opts)
        end

      _ ->
        args ++ [[metadata: metadata]]
    end
  end

  @doc """
  Returns the configured output path for prerendered files.
  """
  @spec output_path() :: String.t()
  def output_path do
    Application.get_env(:phoenix_prerender, :output_path, "priv/static/prerendered")
  end

  @doc """
  Returns the configured URL style (`:dir_index` or `:file`).
  """
  @spec url_style() :: :dir_index | :file
  def url_style do
    Application.get_env(:phoenix_prerender, :url_style, :dir_index)
  end

  @doc """
  Returns whether prerendering is enabled for serving.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:phoenix_prerender, :enabled, false)
  end

  @doc """
  Returns the configured cache-control header value.
  """
  @spec cache_control() :: String.t()
  def cache_control do
    Application.get_env(:phoenix_prerender, :cache_control, "public, max-age=300")
  end

  @doc """
  Returns the configured concurrency level for generation.
  """
  @spec concurrency() :: pos_integer()
  def concurrency do
    Application.get_env(:phoenix_prerender, :concurrency, System.schedulers_online())
  end

  @doc """
  Returns the route private key used to mark prerendered routes.
  """
  @spec route_private_key() :: atom()
  def route_private_key do
    Application.get_env(:phoenix_prerender, :route_private_key, :prerender)
  end

  @doc """
  Returns the route private value used to mark prerendered routes.
  """
  @spec route_private_value() :: term()
  def route_private_value do
    Application.get_env(:phoenix_prerender, :route_private_value, true)
  end
end
