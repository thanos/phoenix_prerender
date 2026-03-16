defmodule PhoenixPrerender.Cluster do
  @moduledoc """
  Distributed regeneration across BEAM nodes.

  Uses `:global.trans/2` for cluster-wide locking to ensure only one
  node regenerates a given page at a time. Uses Phoenix PubSub for
  cache invalidation across nodes.

  ## Configuration

      config :phoenix_prerender,
        pubsub: MyApp.PubSub

  Locks are released automatically if the holding node dies.
  """

  require Logger

  @pubsub_topic "phoenix_prerender"

  @doc """
  Regenerates a page with cluster-wide locking.

  Uses `:global.trans/2` to acquire a distributed lock before
  regenerating. Only one node in the cluster will regenerate
  a given page.

  After successful regeneration, broadcasts to all nodes via PubSub.
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
  Broadcasts a regeneration event to all nodes via PubSub.
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
  Subscribes to regeneration events.

  Call this in processes that need to react to regeneration events
  from other nodes (e.g., to invalidate local caches).
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
  """
  @spec topic() :: String.t()
  def topic, do: @pubsub_topic
end
