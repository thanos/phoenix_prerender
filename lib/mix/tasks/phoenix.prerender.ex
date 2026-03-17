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

    * `--router` -- the Phoenix router module that contains your routes.
      Defaults to `<AppName>Web.Router` (e.g., for app `:my_store`, it
      resolves to `MyStoreWeb.Router`). Use this when your router module
      doesn't follow the standard naming convention.

          $ mix phoenix.prerender --router MyStoreWeb.AdminRouter

    * `--endpoint` -- the Phoenix endpoint module used to render pages.
      Defaults to `<AppName>Web.Endpoint`. Needed when you have multiple
      endpoints or a non-standard module name.

          $ mix phoenix.prerender --endpoint MyStoreWeb.Endpoint

    * `--output` -- the directory where generated HTML files are written.
      Defaults to `"priv/static/prerendered"`. Useful when deploying to
      a CDN origin directory or a separate build artifact path.

          $ mix phoenix.prerender --output _build/static

      **Important:** `PhoenixPrerender.Plug` must be configured to read
      from the same directory, otherwise it won't find the generated files.
      Either set the output path via application config (which both the
      task and plug read automatically):

          config :phoenix_prerender, output_path: "_build/static"

      Or pass it explicitly to the plug:

          plug PhoenixPrerender.Plug, output_path: "_build/static"

    * `--style` -- controls how URL paths map to files on disk. Two options:

        * `"dir_index"` (default) -- each page gets its own directory with
          an `index.html` file. This produces clean URLs without file
          extensions when served by most web servers and CDNs.

              /about     → about/index.html
              /docs/faq  → docs/faq/index.html

        * `"file"` -- each page is written as a single `.html` file.
          Useful when deploying to S3, GitHub Pages, or other hosts that
          don't automatically serve `index.html` from directories.

              /about     → about.html
              /docs/faq  → docs/faq.html

          Example:

              $ mix phoenix.prerender --style file

      **Important:** The plug must use the same style to find the files.
      Set it via application config (recommended):

          config :phoenix_prerender, url_style: :file

      Or pass it to the plug directly:

          plug PhoenixPrerender.Plug, url_style: :file

    * `--path` -- render only specific paths instead of all prerender-marked
      routes. Can be repeated. Useful for regenerating a single page after
      a content change without rebuilding the entire site.

          $ mix phoenix.prerender --path /about
          $ mix phoenix.prerender --path /pricing --path /docs/terms

    * `--concurrency` -- the number of pages to render in parallel. Defaults
      to `System.schedulers_online/0` (the number of CPU cores). Lower this
      on memory-constrained CI runners or when rendering pages that make
      external API calls.

          $ mix phoenix.prerender --concurrency 2

  ## Examples

      # Generate all prerender-marked routes with default settings
      $ mix phoenix.prerender

      # Regenerate just the pricing page after updating copy
      $ mix phoenix.prerender --path /pricing

      # Generate flat .html files for S3 deployment
      $ mix phoenix.prerender --style file --output _build/s3

      # CI pipeline: low concurrency, explicit modules
      $ mix phoenix.prerender --router MyStoreWeb.Router --endpoint MyStoreWeb.Endpoint --concurrency 2

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
        |> then(&("Elixir." <> &1))
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
