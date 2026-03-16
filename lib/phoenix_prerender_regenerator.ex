defmodule PhoenixPrerender.Regenerator do
  @moduledoc """
  Handles incremental static regeneration (ISR) for prerendered pages.

  ISR allows prerendered pages to stay fresh without requiring a full
  rebuild. When a page is requested and found to be stale, it is served
  immediately (stale-while-revalidate) while a background task re-renders
  and writes the updated HTML to disk.

  ## How It Works

    1. A request hits `PhoenixPrerender.Plug` and a prerendered file is found
    2. The plug checks if the file is stale (older than `revalidate` seconds)
    3. If stale, `maybe_regenerate/2` is called to trigger background regeneration
    4. An ETS-based lock prevents multiple processes from regenerating the
       same page simultaneously (thundering herd prevention)
    5. The page is re-rendered through the endpoint and written to disk atomically
    6. The page cache is updated if `PhoenixPrerender.PageCache` is running

  ## Lock Mechanism

  Locks are stored in a `:named_table` ETS table using `insert_new/2`,
  which is atomic. This ensures that only one task per path can be
  regenerating at a time within a single BEAM node. For cluster-wide
  locking, see `PhoenixPrerender.Cluster`.

  ## Configuration

      config :phoenix_prerender,
        # Enable ISR (default: false)
        isr: true,

        # Seconds before a page is considered stale (default: 300)
        revalidate: 300,

        # ISR strategy (default: :stale_while_revalidate)
        strategy: :stale_while_revalidate

  ## Setup

  Add the regenerator to your application supervision tree:

      # lib/my_app/application.ex
      children = [
        # ... other children
        PhoenixPrerender.PageCache,
        {PhoenixPrerender.Regenerator, endpoint: MyAppWeb.Endpoint}
      ]

  ## Telemetry

  Emits `[:phoenix_prerender, :regenerate]` after each regeneration attempt
  with measurements `%{duration: native_time}` and metadata
  `%{path: String.t(), result: :ok | :error}`.
  """

  use GenServer

  require Logger

  @locks_table :phoenix_prerender_locks

  @doc """
  Starts the regenerator GenServer and creates the ETS locks table.

  ## Options

    * `:name` -- the process name (default: `PhoenixPrerender.Regenerator`)
    * `:endpoint` -- the Phoenix endpoint module for rendering
    * `:output_path` -- output directory
      (default: `PhoenixPrerender.output_path/0`)
    * `:url_style` -- URL style, `:dir_index` or `:file`
      (default: `PhoenixPrerender.url_style/0`)

  ## Examples

      {:ok, pid} = PhoenixPrerender.Regenerator.start_link(
        endpoint: MyAppWeb.Endpoint
      )
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the child spec for embedding in a supervision tree.

  ## Examples

      children = [
        {PhoenixPrerender.Regenerator, endpoint: MyAppWeb.Endpoint}
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
    table = :ets.new(@locks_table, [:set, :public, :named_table])

    state = %{
      table: table,
      endpoint: Keyword.get(opts, :endpoint),
      output_path: Keyword.get(opts, :output_path, PhoenixPrerender.output_path()),
      url_style: Keyword.get(opts, :url_style, PhoenixPrerender.url_style())
    }

    {:ok, state}
  end

  @doc """
  Returns whether incremental static regeneration is enabled.

  Reads from the `:isr` application config key. Defaults to `false`.

  ## Examples

      # With default config
      iex> PhoenixPrerender.Regenerator.isr_enabled?()
      false
  """
  @spec isr_enabled?() :: boolean()
  def isr_enabled? do
    Application.get_env(:phoenix_prerender, :isr, false)
  end

  @doc """
  Returns the configured revalidation interval in seconds.

  Pages older than this interval are considered stale and eligible for
  background regeneration. Defaults to `300` (5 minutes).

  ## Examples

      iex> PhoenixPrerender.Regenerator.revalidate_interval()
      300
  """
  @spec revalidate_interval() :: pos_integer()
  def revalidate_interval do
    Application.get_env(:phoenix_prerender, :revalidate, 300)
  end

  @doc """
  Attempts to start a background regeneration for the given path.

  Uses ETS `insert_new/2` for atomic lock acquisition. If another
  process is already regenerating this path, returns
  `:already_regenerating` immediately without blocking.

  When the lock is acquired, a background `Task` is spawned to
  re-render the page. The lock is automatically released when the
  task completes (or crashes).

  ## Parameters

    * `path` -- the URL path to regenerate (e.g., `"/about"`)
    * `endpoint` -- the Phoenix endpoint module

  ## Return Values

    * `:ok` -- regeneration was started in the background
    * `:already_regenerating` -- another task is already handling this path

  ## Examples

      :ok = PhoenixPrerender.Regenerator.maybe_regenerate("/about", MyAppWeb.Endpoint)

      # Second call returns immediately
      :already_regenerating = PhoenixPrerender.Regenerator.maybe_regenerate("/about", MyAppWeb.Endpoint)
  """
  @spec maybe_regenerate(String.t(), module()) :: :ok | :already_regenerating
  def maybe_regenerate(path, endpoint) do
    if acquire_lock(path) do
      spawn_regeneration(path, endpoint)
      :ok
    else
      :already_regenerating
    end
  end

  @doc """
  Checks if a file on disk is stale based on its modification time.

  Compares the file's `mtime` against the configured revalidation
  interval. Returns `true` if the file is older than `revalidate`
  seconds, or if the file does not exist.

  ## Parameters

    * `file_path` -- absolute path to the prerendered HTML file

  ## Examples

      # File exists and was recently written
      false = PhoenixPrerender.Regenerator.file_stale?("priv/static/prerendered/about/index.html")

      # File doesn't exist
      true = PhoenixPrerender.Regenerator.file_stale?("/nonexistent/path.html")
  """
  @spec file_stale?(String.t()) :: boolean()
  def file_stale?(file_path) do
    revalidate = revalidate_interval()

    case File.stat(file_path, time: :posix) do
      {:ok, %{mtime: mtime}} ->
        now = System.os_time(:second)
        now - mtime >= revalidate

      {:error, _} ->
        true
    end
  end

  @doc """
  Regenerates a single page synchronously.

  Renders the path through the endpoint, writes the HTML to disk using
  atomic writes, and updates `PhoenixPrerender.PageCache` if it is
  running. Emits a `[:phoenix_prerender, :regenerate]` telemetry event.

  This function is called internally by the background task spawned
  from `maybe_regenerate/2`, but can also be called directly for
  on-demand regeneration.

  ## Parameters

    * `path` -- the URL path to regenerate
    * `endpoint` -- the Phoenix endpoint module
    * `output_path` -- the base output directory
    * `url_style` -- `:dir_index` or `:file`

  ## Return Values

    * `:ok` -- the page was regenerated successfully
    * `{:error, reason}` -- rendering failed

  ## Examples

      :ok = PhoenixPrerender.Regenerator.regenerate(
        "/about",
        MyAppWeb.Endpoint,
        "priv/static/prerendered",
        :dir_index
      )
  """
  @spec regenerate(String.t(), module(), String.t(), :dir_index | :file) :: :ok | {:error, term()}
  def regenerate(path, endpoint, output_path, url_style) do
    start_time = System.monotonic_time()

    result =
      case PhoenixPrerender.Renderer.render(endpoint, path) do
        {:ok, html} ->
          file_path = PhoenixPrerender.Path.full_output_path(path, output_path, url_style)
          PhoenixPrerender.Generator.write_atomic!(file_path, html)

          # Update page cache if available
          try do
            PhoenixPrerender.PageCache.put(path, html, %{
              file: file_path,
              regenerated_at: DateTime.utc_now() |> DateTime.to_iso8601()
            })
          rescue
            ArgumentError -> :ok
          end

          :ok

        {:error, reason} ->
          Logger.warning("PhoenixPrerender: ISR failed for #{path}: #{inspect(reason)}")
          {:error, reason}
      end

    duration = System.monotonic_time() - start_time
    status = if result == :ok, do: :ok, else: :error

    :telemetry.execute(
      [:phoenix_prerender, :regenerate],
      %{duration: duration},
      %{path: path, result: status}
    )

    result
  end

  defp acquire_lock(path) do
    :ets.insert_new(@locks_table, {path, System.monotonic_time()})
  rescue
    ArgumentError -> false
  end

  defp release_lock(path) do
    :ets.delete(@locks_table, path)
  rescue
    ArgumentError -> true
  end

  defp spawn_regeneration(path, endpoint) do
    output_path = PhoenixPrerender.output_path()
    url_style = PhoenixPrerender.url_style()

    Task.start(fn ->
      try do
        regenerate(path, endpoint, output_path, url_style)
      after
        release_lock(path)
      end
    end)
  end
end
