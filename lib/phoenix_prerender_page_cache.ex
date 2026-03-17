defmodule PhoenixPrerender.PageCache do
  @moduledoc """
  Optional ETS-based in-memory cache for prerendered pages.

  The page cache stores rendered HTML in ETS for fast in-memory serving,
  avoiding disk reads on every request. It is designed for use with
  incremental static regeneration (ISR), where stale content is served
  immediately from cache while a background task regenerates the page.

  ## Serving Order

  When both the cache and `PhoenixPrerender.Plug` are active, the
  serving priority is:

    1. **Memory** -- check the ETS cache for the requested path
    2. **Disk** -- check for a prerendered file on disk
    3. **Phoenix** -- fall through to the live Phoenix application

  ## Setup

  Add the cache to your application supervision tree:

      # lib/my_app/application.ex
      children = [
        # ... other children
        PhoenixPrerender.PageCache,
        PhoenixPrerender.Regenerator
      ]

  ## Staleness

  Each cache entry records a `cached_at` timestamp (monotonic time).
  The `stale?/2` function compares this against the configured
  revalidation interval to determine whether a page should be
  regenerated.

  ## Concurrency

  The ETS table is created with `read_concurrency: true` and `:public`
  access, so any process can read from or write to the cache without
  going through the GenServer. This is important for the serving plug,
  which needs to read cached pages without bottlenecking on a single
  process.

  ## Cache Entries

  Each entry is stored as a 3-tuple: `{path, html, metadata}` where:

    * `path` -- the URL path (e.g., `"/about"`)
    * `html` -- the rendered HTML string
    * `metadata` -- a map with at least `:cached_at` (monotonic time),
      plus any additional metadata passed to `put/3`
  """

  use GenServer

  @table :phoenix_prerender_page_cache

  @doc """
  Starts the page cache GenServer and creates the backing ETS table.

  ## Options

    * `:name` -- the process name (default: `PhoenixPrerender.PageCache`)

  ## Examples

      {:ok, pid} = PhoenixPrerender.PageCache.start_link()

      # With a custom name
      {:ok, pid} = PhoenixPrerender.PageCache.start_link(name: :my_cache)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the child spec for embedding in a supervision tree.

  ## Examples

      children = [
        PhoenixPrerender.PageCache
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @impl true
  def init(opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    prewarm = Keyword.get(opts, :prewarm, PhoenixPrerender.prewarm?())
    output_path = Keyword.get(opts, :output_path, PhoenixPrerender.output_path())
    state = %{table: table, output_path: output_path}

    if prewarm do
      {:ok, state, {:continue, :prewarm}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:prewarm, state) do
    start_time = System.monotonic_time()
    count = do_prewarm(state.output_path)
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:phoenix_prerender, :prewarm],
      %{duration: duration, count: count},
      %{output_path: state.output_path}
    )

    require Logger

    Logger.info("PhoenixPrerender: Prewarmed #{count} pages into cache")

    {:noreply, state}
  end

  defp do_prewarm(output_path) do
    case PhoenixPrerender.Manifest.read(output_path) do
      {:ok, manifest} ->
        pages = manifest["pages"] || []

        safe_prefix =
          case resolve_real_path(output_path) do
            {:ok, real} -> real
            {:error, _} -> Path.expand(output_path)
          end

        Enum.reduce(pages, 0, fn page, count -> prewarm_page(page, count, safe_prefix) end)

      {:error, reason} ->
        require Logger
        Logger.warning("PhoenixPrerender: Prewarm failed to read manifest: #{inspect(reason)}")
        0
    end
  end

  defp prewarm_page(%{"route" => route, "file" => file}, count, safe_prefix)
       when is_binary(route) and is_binary(file) do
    case resolve_real_path(file) do
      {:ok, real_path} ->
        if String.starts_with?(real_path, safe_prefix <> "/") or real_path == safe_prefix do
          read_and_cache(route, real_path, count)
        else
          require Logger

          Logger.warning(
            "PhoenixPrerender: Prewarm skipped #{route}: path outside output directory"
          )

          count
        end

      {:error, _} ->
        # File doesn't exist — fall back to expanded path check for a useful warning
        require Logger
        Logger.warning("PhoenixPrerender: Prewarm skipped #{route}: file not found")
        count
    end
  end

  defp prewarm_page(page, count, _safe_prefix) do
    require Logger
    Logger.warning("PhoenixPrerender: Prewarm skipped malformed entry: #{inspect(page)}")
    count
  end

  # Resolves a path to its real location on disk, following symlinks.
  # Uses File.stat/1 (which follows symlinks) to verify the file exists,
  # then checks via :file.read_link/1 whether it's a symlink and resolves
  # the target if so.
  defp resolve_real_path(path) do
    expanded = Path.expand(path)

    case :file.read_link(String.to_charlist(expanded)) do
      {:ok, target} ->
        {:ok, resolve_symlink_target(target, expanded)}

      {:error, :einval} ->
        resolve_regular_path(expanded)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_symlink_target(target, expanded) do
    target_str = List.to_string(target)

    if Path.type(target_str) == :absolute do
      target_str
    else
      Path.join(Path.dirname(expanded), target_str)
    end
    |> Path.expand()
  end

  defp resolve_regular_path(expanded) do
    case File.stat(expanded) do
      {:ok, _} -> {:ok, expanded}
      {:error, reason} -> {:error, reason}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_and_cache(route, file, count) do
    case File.read(file) do
      {:ok, html} ->
        put(route, html, %{prewarmed: true})
        count + 1

      {:error, reason} ->
        require Logger
        Logger.warning("PhoenixPrerender: Prewarm skipped #{route}: #{inspect(reason)}")
        count
    end
  end

  @doc """
  Looks up a cached page by its URL path.

  Returns `{:ok, html, metadata}` if the page is in cache, or `:miss`
  if no entry exists for the given path. Also returns `:miss` if the
  ETS table does not exist (e.g., cache is not started).

  ## Parameters

    * `path` -- the URL path to look up (e.g., `"/about"`)

  ## Examples

      # Cache hit
      PhoenixPrerender.PageCache.put("/about", "<html>About</html>")
      {:ok, html, metadata} = PhoenixPrerender.PageCache.get("/about")
      html
      #=> "<html>About</html>"

      # Cache miss
      :miss = PhoenixPrerender.PageCache.get("/nonexistent")
  """
  @spec get(String.t()) :: {:ok, String.t(), map()} | :miss
  def get(path) do
    case :ets.lookup(@table, path) do
      [{^path, html, metadata}] -> {:ok, html, metadata}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @doc """
  Stores a page in the cache.

  Automatically adds a `:cached_at` key to the metadata map with the
  current monotonic time. If the path already exists in the cache, it
  is overwritten.

  ## Parameters

    * `path` -- the URL path (e.g., `"/about"`)
    * `html` -- the rendered HTML string
    * `metadata` -- optional metadata map (default: `%{}`)

  ## Examples

      PhoenixPrerender.PageCache.put("/about", "<html>About</html>")

      # With extra metadata
      PhoenixPrerender.PageCache.put("/about", "<html>About</html>", %{
        file: "priv/static/prerendered/about/index.html",
        regenerated_at: "2024-01-15T10:30:00Z"
      })
  """
  @spec put(String.t(), String.t(), map()) :: true
  def put(path, html, metadata \\ %{}) do
    metadata = Map.put(metadata, :cached_at, System.monotonic_time())
    :ets.insert(@table, {path, html, metadata})
  end

  @doc """
  Removes a page from the cache.

  Returns `true` whether or not the path existed. Safe to call even if
  the ETS table does not exist.

  ## Parameters

    * `path` -- the URL path to remove

  ## Examples

      PhoenixPrerender.PageCache.put("/about", "<html>About</html>")
      PhoenixPrerender.PageCache.delete("/about")
      :miss = PhoenixPrerender.PageCache.get("/about")
  """
  @spec delete(String.t()) :: true
  def delete(path) do
    :ets.delete(@table, path)
  rescue
    ArgumentError -> true
  end

  @doc """
  Removes all entries from the cache.

  Returns `true` whether or not the table exists. Useful for bulk
  invalidation or during deployments.

  ## Examples

      PhoenixPrerender.PageCache.put("/about", "<html>About</html>")
      PhoenixPrerender.PageCache.put("/docs", "<html>Docs</html>")
      PhoenixPrerender.PageCache.clear()
      0 = PhoenixPrerender.PageCache.size()
  """
  @spec clear() :: true
  def clear do
    :ets.delete_all_objects(@table)
  rescue
    ArgumentError -> true
  end

  @doc """
  Checks if a cached page is stale and due for regeneration.

  Compares the entry's `cached_at` monotonic timestamp against the
  given revalidation interval. Returns `true` if:

    * The page was cached more than `revalidate_seconds` ago
    * The page is not in the cache
    * The ETS table does not exist

  ## Parameters

    * `path` -- the URL path to check
    * `revalidate_seconds` -- the maximum age in seconds before
      a page is considered stale

  ## Examples

      PhoenixPrerender.PageCache.put("/about", "<html>About</html>")

      # Freshly cached -- not stale
      false = PhoenixPrerender.PageCache.stale?("/about", 300)

      # Not in cache -- always stale
      true = PhoenixPrerender.PageCache.stale?("/missing", 300)
  """
  @spec stale?(String.t(), pos_integer()) :: boolean()
  def stale?(path, revalidate_seconds) do
    case :ets.lookup(@table, path) do
      [{^path, _html, %{cached_at: cached_at}}] ->
        age = System.monotonic_time() - cached_at
        age_seconds = System.convert_time_unit(age, :native, :second)
        age_seconds >= revalidate_seconds

      _ ->
        true
    end
  rescue
    ArgumentError -> true
  end

  @doc """
  Returns the number of pages currently in the cache.

  Returns `0` if the ETS table does not exist.

  ## Examples

      PhoenixPrerender.PageCache.put("/about", "<html>About</html>")
      PhoenixPrerender.PageCache.put("/docs", "<html>Docs</html>")
      2 = PhoenixPrerender.PageCache.size()
  """
  @spec size() :: non_neg_integer()
  def size do
    :ets.info(@table, :size)
  rescue
    ArgumentError -> 0
  end
end
