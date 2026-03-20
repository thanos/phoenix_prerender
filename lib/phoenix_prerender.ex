defmodule PhoenixPrerender do
  @moduledoc """
  Static prerendering and incremental regeneration for Phoenix applications.

  PhoenixPrerender generates static HTML files from Phoenix routes at build
  time and serves them directly from disk in production. It also supports
  incremental static regeneration (ISR) where stale pages are served
  immediately while being regenerated in the background, and distributed
  regeneration across BEAM nodes.

  ## Overview

  The library provides three modes of operation:

    1. **Build-time static generation** -- Run `mix phoenix.prerender` to
       render marked routes through the full Phoenix endpoint pipeline and
       write the HTML output to disk.

    2. **Production static serving** -- `PhoenixPrerender.Plug` intercepts
       requests and serves prerendered files when available, falling through
       to the Phoenix application otherwise.

    3. **Incremental static regeneration** -- When ISR is enabled, stale
       pages are served immediately while a background task re-renders and
       writes the updated HTML. ETS-based locks prevent thundering herd.

  ## Configuration

  All configuration lives under the `:phoenix_prerender` application key:

      config :phoenix_prerender,
        # Whether the serving plug is active (default: false)
        enabled: false,

        # Directory where generated HTML files are written
        output_path: "priv/static/prerendered",

        # How URL paths map to files -- :dir_index or :file
        url_style: :dir_index,

        # Cache-Control header value for served pages
        cache_control: "public, max-age=300",

        # Metadata key used to mark routes for prerendering
        route_private_key: :prerender,

        # Metadata value that marks a route for prerendering
        route_private_value: true,

        # Number of concurrent rendering tasks
        concurrency: System.schedulers_online(),

        # Enable incremental static regeneration
        isr: false,

        # Seconds before a page is considered stale (ISR)
        revalidate: 300,

        # ISR strategy
        strategy: :stale_while_revalidate,

        # Base URL for sitemap generation
        base_url: "https://example.com",

        # Only serve paths listed in manifest.json
        strict_paths: true,

        # Only serve prerendered pages to search engine crawlers.
        # When true, browsers get passed through to the live app.
        # Useful for LiveView routes where prerendered HTML is for SEO only.
        bots_only: false,

        # PubSub server for distributed cache invalidation
        pubsub: nil,

        # List of compressor modules for pre-compression (default: [])
        compressors: [],

        # Prewarm the ETS cache from manifest on boot (default: false)
        prewarm: false

  ## Marking Routes

  Routes are marked for prerendering by adding metadata in the router:

      # Explicit metadata
      get "/about", PageController, :about, metadata: %{prerender: true}
      live "/docs/terms", TermsLive, :index, metadata: %{prerender: true}

  Or using the `prerender/1` macro for convenience:

      import PhoenixPrerender

      scope "/", MyAppWeb do
        pipe_through :browser

        prerender do
          get "/about", PageController, :about
          get "/pricing", PageController, :pricing
          live "/docs/terms", TermsLive
        end
      end

  ## Generating Pages

  Run the Mix task to generate static files:

      mix phoenix.prerender

  Or with explicit options:

      mix phoenix.prerender --router MyAppWeb.Router --endpoint MyAppWeb.Endpoint
      mix phoenix.prerender --path /about --path /pricing

  ## Serving Pages

  Add the plug to your endpoint, before the router:

      # In your endpoint.ex
      plug PhoenixPrerender.Plug

  And enable it in your production config:

      config :phoenix_prerender, enabled: true

  ## Verified Routes

  Prerendered paths are fully compatible with Phoenix verified routes:

      ~p"/about"
      ~p"/docs/terms"

  Generated files always match the canonical paths from the router.
  """

  @doc """
  Wraps route definitions and injects `metadata: %{prerender: true}`.

  This macro is used inside a Phoenix router `scope` block to mark
  multiple routes for prerendering without repeating the metadata option
  on each route.

  Supports `get`, `post`, `put`, `patch`, `delete`, and `live` route
  definitions. Any other expressions in the block are passed through
  unchanged.

  ## Example

      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        import PhoenixPrerender

        scope "/", MyAppWeb do
          pipe_through :browser

          prerender do
            get "/about", PageController, :about
            get "/pricing", PageController, :pricing
            live "/changelog", ChangelogLive
          end

          # This route is NOT prerendered
          get "/contact", PageController, :contact
        end
      end

  The above is equivalent to:

      get "/about", PageController, :about, metadata: %{prerender: true}
      get "/pricing", PageController, :pricing, metadata: %{prerender: true}
      live "/changelog", ChangelogLive, metadata: %{prerender: true}
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

  defp inject_single({:live, _meta, _args} = expr), do: expr

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
  Returns the configured output directory for prerendered files.

  Defaults to `"priv/static/prerendered"`.

  ## Examples

      iex> PhoenixPrerender.output_path()
      "priv/static/prerendered"
  """
  @spec output_path() :: String.t()
  def output_path do
    Application.get_env(:phoenix_prerender, :output_path, "priv/static/prerendered")
  end

  @doc """
  Returns the configured URL style used for path-to-file mapping.

  Two styles are supported:

    * `:dir_index` (default) -- `/about` becomes `about/index.html`
    * `:file` -- `/about` becomes `about.html`

  ## Examples

      iex> PhoenixPrerender.url_style()
      :dir_index
  """
  @spec url_style() :: :dir_index | :file
  def url_style do
    Application.get_env(:phoenix_prerender, :url_style, :dir_index)
  end

  @doc """
  Returns whether prerendering is enabled for serving.

  When `false` (the default), `PhoenixPrerender.Plug` passes all
  requests through without checking for prerendered files.

  ## Examples

      iex> PhoenixPrerender.enabled?()
      false
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:phoenix_prerender, :enabled, false)
  end

  @doc """
  Returns the configured `Cache-Control` header value for served pages.

  Defaults to `"public, max-age=300"`.

  ## Examples

      iex> PhoenixPrerender.cache_control()
      "public, max-age=300"
  """
  @spec cache_control() :: String.t()
  def cache_control do
    Application.get_env(:phoenix_prerender, :cache_control, "public, max-age=300")
  end

  @doc """
  Returns the configured concurrency level for generation tasks.

  Controls how many pages are rendered in parallel via
  `Task.async_stream/3`. Defaults to `System.schedulers_online/0`.

  ## Examples

      iex> PhoenixPrerender.concurrency() > 0
      true
  """
  @spec concurrency() :: pos_integer()
  def concurrency do
    Application.get_env(:phoenix_prerender, :concurrency, System.schedulers_online())
  end

  @doc """
  Returns the metadata key used to identify prerendered routes.

  Routes with this key set in their metadata map are discovered by
  `PhoenixPrerender.Route.discover/2`. Defaults to `:prerender`.

  ## Examples

      iex> PhoenixPrerender.route_private_key()
      :prerender
  """
  @spec route_private_key() :: atom()
  def route_private_key do
    Application.get_env(:phoenix_prerender, :route_private_key, :prerender)
  end

  @doc """
  Returns the metadata value that marks a route for prerendering.

  Only routes whose metadata value for `route_private_key/0` matches
  this value are selected for generation. Defaults to `true`.

  ## Examples

      iex> PhoenixPrerender.route_private_value()
      true
  """
  @spec route_private_value() :: term()
  def route_private_value do
    Application.get_env(:phoenix_prerender, :route_private_value, true)
  end

  @doc """
  Returns whether strict path checking is enabled.

  When `true` (the default), `PhoenixPrerender.Plug` only serves pages
  whose paths appear in `manifest.json`. This prevents serving arbitrary
  files that happen to exist in the output directory.

  ## Examples

      iex> PhoenixPrerender.strict_paths()
      true
  """
  @spec strict_paths() :: boolean()
  def strict_paths do
    Application.get_env(:phoenix_prerender, :strict_paths, true)
  end

  @doc """
  Returns the list of configured compressor modules.

  Defaults to `[]` (no pre-compression). See `PhoenixPrerender.Compressor`
  for details on configuring compressors.

  ## Examples

      iex> PhoenixPrerender.compressors()
      []
  """
  @spec compressors() :: [module()]
  def compressors do
    Application.get_env(:phoenix_prerender, :compressors, [])
  end

  @doc """
  Returns whether cache prewarming is enabled.

  When `true`, `PhoenixPrerender.PageCache` loads all pages from the
  manifest into ETS on boot, eliminating first-request disk reads.
  Defaults to `false`.

  ## Examples

      iex> PhoenixPrerender.prewarm?()
      false
  """
  @spec prewarm?() :: boolean()
  def prewarm? do
    Application.get_env(:phoenix_prerender, :prewarm, false)
  end

  @doc """
  Resolves an asset path to its digested counterpart via the endpoint.

  Delegates to `PhoenixPrerender.StaticAsset.static_path/2`. See that
  module for full documentation.

  ## Examples

      PhoenixPrerender.static_asset_path(MyAppWeb.Endpoint, "/assets/app.css")
      #=> "/assets/app-ABC123.css"
  """
  @spec static_asset_path(module(), String.t()) :: String.t()
  defdelegate static_asset_path(endpoint, path),
    to: PhoenixPrerender.StaticAsset,
    as: :static_path
end
