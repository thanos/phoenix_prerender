defmodule Mix.Tasks.Phoenix.Prerender do
  @moduledoc """
  Generates static HTML files from Phoenix routes marked for prerendering.

  This Mix task discovers all routes annotated with `metadata: %{prerender: true}`
  (or using the `prerender/1` macro), renders each one through the full
  Phoenix endpoint pipeline, and writes the resulting HTML files to disk.

  After generation, a `manifest.json` and `sitemap.xml` are also written
  to the output directory.

  ## Usage

      $ mix phoenix.prerender

  The task automatically infers the router and endpoint modules from
  your application name (e.g., `MyApp` → `MyAppWeb.Router` and
  `MyAppWeb.Endpoint`). Override with `--router` and `--endpoint`
  if your modules use a different naming convention.

  ## Options

    * `--router` -- the router module name (default: inferred from app name)
    * `--endpoint` -- the endpoint module name (default: inferred from app name)
    * `--output` -- output directory for generated files
      (default: from config or `"priv/static/prerendered"`)
    * `--style` -- URL style: `"dir_index"` or `"file"`
      (default: from config or `"dir_index"`)
    * `--path` -- render only specific path(s); can be repeated
    * `--concurrency` -- number of concurrent rendering tasks
      (default: from config or `System.schedulers_online/0`)

  ## Examples

      # Generate all prerender-marked routes
      $ mix phoenix.prerender

      # Specify router and endpoint explicitly
      $ mix phoenix.prerender --router MyAppWeb.Router --endpoint MyAppWeb.Endpoint

      # Generate only specific pages
      $ mix phoenix.prerender --path /about --path /docs/terms

      # Use file-style URL mapping (about.html instead of about/index.html)
      $ mix phoenix.prerender --style file

      # Limit concurrency to 2 tasks
      $ mix phoenix.prerender --concurrency 2

      # Generate to a custom directory
      $ mix phoenix.prerender --output _build/prerendered

  ## Output

  The task prints progress information to the console:

      PhoenixPrerender: Discovering routes from MyAppWeb.Router...
      PhoenixPrerender: Generated 5 pages to priv/static/prerendered

  If any pages fail to render, errors are listed individually:

      PhoenixPrerender: 1 pages failed to generate
        - /broken: {:unexpected_status, 500, "/broken"}

  ## Exit Codes

  The task always exits with status 0, even if some pages fail. Check
  the output for failure details. This allows CI pipelines to continue
  and report partial results.

  ## CI Integration

  Add the task to your CI/CD pipeline to generate static pages before
  deployment:

      # In your CI config
      mix deps.get
      mix compile
      mix phoenix.prerender
      mix phx.digest  # Include prerendered files in the digest

  ## How Module Resolution Works

  When `--router` or `--endpoint` are not provided, the task:

    1. Reads the `:app` key from `mix.exs` (e.g., `:my_app`)
    2. Converts to CamelCase (e.g., `"MyApp"`)
    3. Appends `"Web.Router"` or `"Web.Endpoint"`
    4. Resolves via `String.to_existing_atom/1`

  If resolution fails, the task raises with a message asking you to
  specify the flag explicitly.
  """

  use Mix.Task

  @shortdoc "Generate static HTML from prerendered Phoenix routes"

  @switches [
    router: :string,
    endpoint: :string,
    output: :string,
    style: :string,
    path: [:string, :keep],
    concurrency: :integer
  ]

  @doc """
  Runs the prerender generation task.

  Parses command-line arguments, starts the application, resolves the
  router and endpoint modules, and delegates to
  `PhoenixPrerender.Generator.generate/1`.

  ## Parameters

    * `args` -- command-line arguments (parsed by `OptionParser`)
  """
  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    Mix.Task.run("app.start")

    router = resolve_module(opts, :router, "Web.Router")
    endpoint = resolve_module(opts, :endpoint, "Web.Endpoint")
    output_path = Keyword.get(opts, :output, PhoenixPrerender.output_path())

    url_style =
      case Keyword.get(opts, :style) do
        "file" -> :file
        "dir_index" -> :dir_index
        nil -> PhoenixPrerender.url_style()
        other -> Mix.raise("Invalid URL style: #{other}. Must be 'dir_index' or 'file'.")
      end

    concurrency = Keyword.get(opts, :concurrency, PhoenixPrerender.concurrency())

    paths =
      case Keyword.get_values(opts, :path) do
        [] -> nil
        explicit -> explicit
      end

    Mix.shell().info("PhoenixPrerender: Discovering routes from #{inspect(router)}...")

    gen_opts = [
      router: router,
      endpoint: endpoint,
      output_path: output_path,
      url_style: url_style,
      concurrency: concurrency
    ]

    gen_opts = if paths, do: Keyword.put(gen_opts, :paths, paths), else: gen_opts

    {:ok, results} = PhoenixPrerender.Generator.generate(gen_opts)

    successes = Enum.count(results, &(&1.status == :ok))
    failures = Enum.count(results, &(&1.status == :error))

    Mix.shell().info("PhoenixPrerender: Generated #{successes} pages to #{output_path}")

    if failures > 0 do
      Mix.shell().error("PhoenixPrerender: #{failures} pages failed to generate")

      results
      |> Enum.filter(&(&1.status == :error))
      |> Enum.each(fn result ->
        Mix.shell().error("  - #{result.path}: #{inspect(result[:error])}")
      end)
    end
  end

  @doc false
  defp resolve_module(opts, key, suffix) do
    case Keyword.get(opts, key) do
      nil ->
        app = Mix.Project.config()[:app]

        app
        |> Atom.to_string()
        |> Macro.camelize()
        |> Kernel.<>(suffix)
        |> String.to_existing_atom()

      module_string ->
        String.to_existing_atom("Elixir." <> module_string)
    end
  rescue
    ArgumentError ->
      Mix.raise(
        "Could not resolve #{key} module. " <>
          "Please specify --#{key} explicitly."
      )
  end
end
