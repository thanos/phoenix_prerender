defmodule PhoenixPrerender.PageCache do
  @moduledoc """
  Optional ETS-based in-memory cache for prerendered pages.

  Provides fast serving from memory before falling back to disk.
  Used by the ISR system to serve stale content while regenerating.

  ## Usage

  Start the cache in your application supervision tree:

      children = [
        PhoenixPrerender.PageCache
      ]

  The serving order is: memory -> disk -> Phoenix fallback.
  """

  use GenServer

  @table :phoenix_prerender_page_cache

  @doc """
  Starts the page cache process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the child spec for supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @doc """
  Gets a cached page by path.

  Returns `{:ok, html, metadata}` if found, `:miss` otherwise.
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
  Puts a page into the cache.
  """
  @spec put(String.t(), String.t(), map()) :: true
  def put(path, html, metadata \\ %{}) do
    metadata = Map.put(metadata, :cached_at, System.monotonic_time())
    :ets.insert(@table, {path, html, metadata})
  end

  @doc """
  Removes a page from the cache.
  """
  @spec delete(String.t()) :: true
  def delete(path) do
    :ets.delete(@table, path)
  rescue
    ArgumentError -> true
  end

  @doc """
  Clears all cached pages.
  """
  @spec clear() :: true
  def clear do
    :ets.delete_all_objects(@table)
  rescue
    ArgumentError -> true
  end

  @doc """
  Checks if a cached page is stale based on the revalidation interval.

  Returns `true` if the page was cached more than `revalidate` seconds ago.
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
  Returns the number of cached pages.
  """
  @spec size() :: non_neg_integer()
  def size do
    :ets.info(@table, :size)
  rescue
    ArgumentError -> 0
  end
end
