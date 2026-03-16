defmodule PhoenixPrerender.Generator do
  @moduledoc """
  Generates static HTML files from Phoenix routes.

  Uses `Task.async_stream/3` for concurrent generation with
  configurable concurrency. All file writes are atomic (write to
  temporary file, then rename).
  """

  require Logger

  @doc """
  Generates prerendered HTML files for all discovered routes.

  ## Options

    * `:router` - the Phoenix router module (required)
    * `:endpoint` - the Phoenix endpoint module (required)
    * `:output_path` - output directory (default: configured value)
    * `:url_style` - URL style (default: configured value)
    * `:concurrency` - number of concurrent tasks (default: configured value)
    * `:paths` - explicit list of paths to render (overrides route discovery)

  Returns `{:ok, results}` where results is a list of generation outcomes.
  """
  @spec generate(keyword()) :: {:ok, [map()]}
  def generate(opts) do
    router = Keyword.fetch!(opts, :router)
    endpoint = Keyword.fetch!(opts, :endpoint)
    output_path = Keyword.get(opts, :output_path, PhoenixPrerender.output_path())
    url_style = Keyword.get(opts, :url_style, PhoenixPrerender.url_style())
    concurrency = Keyword.get(opts, :concurrency, PhoenixPrerender.concurrency())

    paths =
      case Keyword.get(opts, :paths) do
        nil -> PhoenixPrerender.Route.paths(router)
        explicit -> explicit
      end

    File.mkdir_p!(output_path)

    start_time = System.monotonic_time()

    results =
      paths
      |> Task.async_stream(
        fn path -> generate_page(endpoint, path, output_path, url_style) end,
        max_concurrency: concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> %{status: :error, error: reason}
      end)

    duration = System.monotonic_time() - start_time
    successes = Enum.count(results, &(&1.status == :ok))
    failures = Enum.count(results, &(&1.status == :error))

    :telemetry.execute(
      [:phoenix_prerender, :generate],
      %{duration: duration, count: length(results), successes: successes, failures: failures},
      %{output_path: output_path}
    )

    Logger.info(
      "PhoenixPrerender: Generated #{successes} pages" <>
        if(failures > 0, do: " (#{failures} failures)", else: "")
    )

    manifest_entries = Enum.filter(results, &(&1.status == :ok))
    PhoenixPrerender.Manifest.write(manifest_entries, output_path)
    PhoenixPrerender.Manifest.write_sitemap(manifest_entries, output_path)

    {:ok, results}
  end

  @doc """
  Generates a single page. Returns a result map.
  """
  @spec generate_page(module(), String.t(), String.t(), :dir_index | :file) :: map()
  def generate_page(endpoint, path, output_path, url_style) do
    file_path = PhoenixPrerender.Path.full_output_path(path, output_path, url_style)
    start_time = System.monotonic_time()

    case PhoenixPrerender.Renderer.render(endpoint, path) do
      {:ok, html} ->
        write_atomic!(file_path, html)
        duration = System.monotonic_time() - start_time
        checksum = :crypto.hash(:sha256, html) |> Base.encode16(case: :lower)

        %{
          status: :ok,
          path: path,
          file: file_path,
          size: byte_size(html),
          checksum: checksum,
          generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          duration: duration
        }

      {:error, reason} ->
        Logger.warning("PhoenixPrerender: Failed to render #{path}: #{inspect(reason)}")
        %{status: :error, path: path, error: reason}
    end
  end

  @doc """
  Writes content to a file atomically.

  Writes to a temporary file first, then renames to the target path.
  This prevents serving partially written files.
  """
  @spec write_atomic!(String.t(), String.t()) :: :ok
  def write_atomic!(file_path, content) do
    dir = Path.dirname(file_path)
    File.mkdir_p!(dir)

    tmp_path = file_path <> ".tmp"
    File.write!(tmp_path, content)
    File.rename!(tmp_path, file_path)
  end
end
