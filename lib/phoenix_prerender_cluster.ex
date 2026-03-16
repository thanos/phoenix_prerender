defmodule PhoenixPrerender.Cluster do
  @moduledoc """
  Distributed regeneration and cache invalidation across BEAM nodes.

  When running a Phoenix application on multiple nodes,
  `PhoenixPrerender.Cluster` ensures that:

    1. **Only one node regenerates a given page** -- uses `:global.trans/2`
       for cluster-wide locking, so duplicate work is avoided even across
       nodes.

    2. **All nodes invalidate their caches** -- after regeneration, a
       PubSub broadcast notifies all nodes to clear the stale entry from
       their local `PhoenixPrerender.PageCache`.

  ## How It Works

    1. A node detects a stale page and calls `regenerate/4`
    2. `:global.trans/2` acquires a cluster-wide lock keyed by
       `{:phoenix_prerender, path}`
    3. Inside the lock, `PhoenixPrerender.Regenerator.regenerate/4` renders
       the page and writes it to disk
    4. On success, `broadcast_regenerated/1` publishes a `{:regenerated, path}`
       message via Phoenix PubSub
    5. Subscribed nodes receive the message and call `handle_regenerated/1`
       to clear their local page cache

  If the node holding the lock crashes, `:global` automatically releases
  the lock, so other nodes can pick up the work.

  ## Configuration

      config :phoenix_prerender,
        # The Phoenix.PubSub server for cross-node broadcasts
        pubsub: MyApp.PubSub

  If `:pubsub` is not configured, broadcasts are silently skipped (useful
  for single-node deployments).

  ## Setup

  Subscribe to regeneration events in a process that should react to
  cross-node regenerations (e.g., in a GenServer's `init/1`):

      def init(state) do
        PhoenixPrerender.Cluster.subscribe()
        {:ok, state}
      end

      def handle_info({:regenerated, path}, state) do
        PhoenixPrerender.Cluster.handle_regenerated(path)
        {:noreply, state}
      end

  ## PubSub Topic

  All messages are broadcast on the `"phoenix_prerender"` topic. The
  message format is `{:regenerated, path}` where `path` is the URL
  path string (e.g., `"/about"`).
  """

  require Logger

  @pubsub_topic "phoenix_prerender"

  @doc """
  Regenerates a page with cluster-wide locking.

  Acquires a distributed lock via `:global.trans/2` using the key
  `{:phoenix_prerender, path}`, then delegates to
  `PhoenixPrerender.Regenerator.regenerate/4`. After successful
  regeneration, broadcasts to all nodes via PubSub.

  If another node is already holding the lock for this path, this
  call blocks until the lock is released.

  ## Parameters

    * `path` -- the URL path to regenerate (e.g., `"/about"`)
    * `endpoint` -- the Phoenix endpoint module
    * `output_path` -- the base output directory
    * `url_style` -- `:dir_index` or `:file`

  ## Return Values

    * `:ok` -- the page was regenerated and broadcast sent
    * `{:error, reason}` -- rendering failed (no broadcast sent)

  ## Examples

      :ok = PhoenixPrerender.Cluster.regenerate(
        "/about",
        MyAppWeb.Endpoint,
        "priv/static/prerendered",
        :dir_index
      )
  """
  @spec regenerate(String.t(), module(), String.t(), :dir_index | :file) :: :ok | {:error, term()}
  def regenerate(path, endpoint, output_path, url_style) do
    lock_id = {:phoenix_prerender, path}

    result =
      :global.trans(lock_id, fn ->
        PhoenixPrerender.Regenerator.regenerate(path, endpoint, output_path, url_style)
      end)

    case result do
      :ok ->
        broadcast_regenerated(path)
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Broadcasts a regeneration event to all nodes via Phoenix PubSub.

  Publishes `{:regenerated, path}` on the `"phoenix_prerender"` topic.
  If no PubSub server is configured, logs a debug message and returns
  `:ok`.

  ## Parameters

    * `path` -- the URL path that was regenerated

  ## Return Values

    * `:ok` -- broadcast sent (or no PubSub configured)
    * `{:error, reason}` -- PubSub broadcast failed

  ## Examples

      :ok = PhoenixPrerender.Cluster.broadcast_regenerated("/about")
  """
  @spec broadcast_regenerated(String.t()) :: :ok | {:error, term()}
  def broadcast_regenerated(path) do
    case pubsub() do
      nil ->
        Logger.debug("PhoenixPrerender: No PubSub configured, skipping broadcast")
        :ok

      pubsub ->
        Phoenix.PubSub.broadcast(pubsub, @pubsub_topic, {:regenerated, path})
    end
  end

  @doc """
  Subscribes the current process to regeneration events from other nodes.

  After subscribing, the process will receive messages of the form
  `{:regenerated, path}` whenever any node in the cluster regenerates
  a page.

  ## Return Values

    * `:ok` -- successfully subscribed
    * `{:error, :no_pubsub}` -- no PubSub server configured

  ## Examples

      :ok = PhoenixPrerender.Cluster.subscribe()

      # In a GenServer handle_info:
      def handle_info({:regenerated, path}, state) do
        PhoenixPrerender.Cluster.handle_regenerated(path)
        {:noreply, state}
      end
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    case pubsub() do
      nil -> {:error, :no_pubsub}
      pubsub -> Phoenix.PubSub.subscribe(pubsub, @pubsub_topic)
    end
  end

  @doc """
  Handles a regeneration broadcast by invalidating the local page cache.

  Call this from a process that has subscribed via `subscribe/0` when
  it receives a `{:regenerated, path}` message. Deletes the stale
  entry from `PhoenixPrerender.PageCache` so the next request reads
  the fresh file from disk.

  Safe to call even if the page cache is not running.

  ## Parameters

    * `path` -- the URL path that was regenerated on another node

  ## Examples

      # In a GenServer:
      def handle_info({:regenerated, path}, state) do
        PhoenixPrerender.Cluster.handle_regenerated(path)
        {:noreply, state}
      end
  """
  @spec handle_regenerated(String.t()) :: :ok
  def handle_regenerated(path) do
    try do
      PhoenixPrerender.PageCache.delete(path)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  defp pubsub do
    Application.get_env(:phoenix_prerender, :pubsub)
  end

  @doc """
  Returns the PubSub topic used for regeneration broadcasts.

  All cross-node regeneration messages are published on this topic.

  ## Examples

      iex> PhoenixPrerender.Cluster.topic()
      "phoenix_prerender"
  """
  @spec topic() :: String.t()
  def topic, do: @pubsub_topic
end
