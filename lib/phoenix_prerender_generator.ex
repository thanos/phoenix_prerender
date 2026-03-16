defmodule PhoenixPrerender.Generator do
  @moduledoc """
  Generates static HTML files from Phoenix routes.

  The generator discovers prerender-marked routes, renders each one
  through the full endpoint pipeline using `PhoenixPrerender.Renderer`,
  and writes the HTML output to disk using atomic writes.

  Rendering is concurrent via `Task.async_stream/3` with configurable
  concurrency (defaults to `System.schedulers_online/0`).

  After generation, a `manifest.json` and `sitemap.xml` are written
  to the output directory.

  ## Atomic Writes

  All file writes use a two-step process:

    1. Write content to `<path>.tmp`
    2. Rename `<path>.tmp` to `<path>`

  This prevents the serving plug from ever reading a partially written
  file, which is important during ISR regeneration where pages may be
  regenerated while being served.

  ## Example

      {:ok, results} = PhoenixPrerender.Generator.generate(
        router: MyAppWeb.Router,
        endpoint: MyAppWeb.Endpoint
      )

      Enum.each(results, fn
        %{status: :ok, path: path, file: file} ->
          IO.puts("Generated \#{path} -> \#{file}")
        %{status: :error, path: path, error: reason} ->
          IO.puts("Failed \#{path}: \#{inspect(reason)}")
      end)

  ## Telemetry

  Emits `[:phoenix_prerender, :generate]` after a full generation run with:

    * Measurements: `%{duration: native_time, count: integer, successes: integer, failures: integer}`
    * Metadata: `%{output_path: String.t()}`
  """

  require Logger

  @doc """
  Generates prerendered HTML files for all discovered routes.

  Discovers routes from the given router, renders each through the
  endpoint, and writes the output to disk. Also generates
  `manifest.json` and `sitemap.xml` files.

  ## Options

    * `:router` -- the Phoenix router module (required)
    * `:endpoint` -- the Phoenix endpoint module (required)
    * `:output_path` -- output directory
      (default: `PhoenixPrerender.output_path/0`)
    * `:url_style` -- URL style, `:dir_index` or `:file`
      (default: `PhoenixPrerender.url_style/0`)
    * `:concurrency` -- number of concurrent rendering tasks
      (default: `PhoenixPrerender.concurrency/0`)
    * `:paths` -- explicit list of URL paths to render; when provided,
      route discovery is skipped

  ## Return Value

  Returns `{:ok, results}` where `results` is a list of maps. Each map
  has a `:status` key that is either `:ok` or `:error`:

      # Success entry
      %{
        status: :ok,
        path: "/about",
        file: "priv/static/prerendered/about/index.html",
        size: 4521,
        checksum: "a1b2c3...",
        generated_at: "2024-01-15T10:30:00Z",
        duration: 1234567
      }

      # Error entry
      %{status: :error, path: "/broken", error: {:unexpected_status, 500, "/broken"}}

  ## Examples

      # Generate all prerender routes
      {:ok, results} = PhoenixPrerender.Generator.generate(
        router: MyAppWeb.Router,
        endpoint: MyAppWeb.Endpoint
      )

      # Generate specific paths only
      {:ok, results} = PhoenixPrerender.Generator.generate(
        router: MyAppWeb.Router,
        endpoint: MyAppWeb.Endpoint,
        paths: ["/about", "/pricing"]
      )

      # Custom output directory and URL style
      {:ok, results} = PhoenixPrerender.Generator.generate(
        router: MyAppWeb.Router,
        endpoint: MyAppWeb.Endpoint,
        output_path: "/tmp/prerendered",
        url_style: :file
      )
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
  Generates a single prerendered page.

  Renders the path through the endpoint, writes the HTML to the
  output directory using atomic writes, and returns a result map
  with metadata including file size and SHA-256 checksum.

  ## Parameters

    * `endpoint` -- the Phoenix endpoint module
    * `path` -- the URL path to render (e.g., `"/about"`)
    * `output_path` -- the base output directory
    * `url_style` -- `:dir_index` or `:file`

  ## Return Value

  On success:

      %{
        status: :ok,
        path: "/about",
        file: "priv/static/prerendered/about/index.html",
        size: 4521,
        checksum: "a1b2c3d4...",
        generated_at: "2024-01-15T10:30:00Z",
        duration: 1234567
      }

  On failure:

      %{status: :error, path: "/broken", error: {:unexpected_status, 500, "/broken"}}
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

  Creates any missing parent directories, writes content to a `.tmp`
  file, then renames it to the final path. This two-step process ensures
  that readers never see a partially written file.

  ## Parameters

    * `file_path` -- the final destination path
    * `content` -- the string content to write

  ## Examples

      PhoenixPrerender.Generator.write_atomic!("output/about/index.html", "<html>...</html>")
      File.read!("output/about/index.html")
      #=> "<html>...</html>"
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
