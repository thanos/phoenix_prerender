defmodule PhoenixPrerender.Regenerator do
  @moduledoc """
  Handles incremental static regeneration (ISR).

  Uses ETS-based locks to prevent thundering herd problems.
  Only one regeneration per path can run at a time. Stale content
  is served immediately while regeneration happens in the background.

  ## Configuration

      config :phoenix_prerender,
        isr: true,
        revalidate: 300,
        strategy: :stale_while_revalidate
  """

  use GenServer

  require Logger

  @locks_table :phoenix_prerender_locks

  @doc """
  Starts the regenerator process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

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
  Checks if ISR is enabled.
  """
  @spec isr_enabled?() :: boolean()
  def isr_enabled? do
    Application.get_env(:phoenix_prerender, :isr, false)
  end

  @doc """
  Returns the configured revalidation interval in seconds.
  """
  @spec revalidate_interval() :: pos_integer()
  def revalidate_interval do
    Application.get_env(:phoenix_prerender, :revalidate, 300)
  end

  @doc """
  Attempts to regenerate a page in the background.

  Uses ETS insert_new for lock acquisition. If another process is already
  regenerating this path, returns `:already_regenerating`.

  Returns `:ok` if regeneration was started, `:already_regenerating` otherwise.
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
  Checks if a file is stale based on its modification time.
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
