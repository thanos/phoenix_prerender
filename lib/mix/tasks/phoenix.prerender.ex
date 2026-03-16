defmodule Mix.Tasks.Phoenix.Prerender do
  @moduledoc """
  Generates static HTML files from Phoenix routes marked for prerendering.

  ## Usage

      mix phoenix.prerender

  ## Options

    * `--router` - the router module (default: inferred from app)
    * `--endpoint` - the endpoint module (default: inferred from app)
    * `--output` - output directory (default: configured or "priv/static/prerendered")
    * `--style` - URL style, "dir_index" or "file" (default: configured or "dir_index")
    * `--path` - render only specific path(s), can be repeated
    * `--concurrency` - number of concurrent tasks (default: configured or schedulers_online)

  ## Examples

      mix phoenix.prerender
      mix phoenix.prerender --router MyAppWeb.Router --endpoint MyAppWeb.Endpoint
      mix phoenix.prerender --path /about --path /docs/terms
      mix phoenix.prerender --style file
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
