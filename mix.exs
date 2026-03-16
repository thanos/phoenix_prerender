defmodule PhoenixPrerender.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/thanos/phoenix_prerender"

  def project do
    [
      app: :phoenix_prerender,
      version: @version,
      elixir: "~> 1.15",
      name: "PhoenixPrerender",
      description:
        "Static prerendering and incremental static regeneration (ISR) for Phoenix applications.",
      source_url: @source_url,
      homepage_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime dependencies (used by core library modules)
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.2"},

      # Test host app (PhoenixPrerenderWeb.* in test/support)
      {:bandit, "~> 1.5", only: [:dev, :test]},
      {:gettext, "~> 1.0", only: [:dev, :test]},
      {:telemetry_metrics, "~> 1.0", only: [:dev, :test]},
      {:telemetry_poller, "~> 1.0", only: [:dev, :test]},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8.3", only: :dev},
      {:esbuild, "~> 0.10", only: :dev, runtime: false},
      {:tailwind, "~> 0.3", only: :dev, runtime: false},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1,
       only: :dev},
      {:dns_cluster, "~> 0.2.0", only: :dev},

      # Dev tools
      {:ex_doc, "~> 0.36", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},

      # Test only
      {:lazy_html, ">= 0.1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Thanos Vassilakis"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(
        lib/phoenix_prerender.ex
        lib/phoenix_prerender_cluster.ex
        lib/phoenix_prerender_generator.ex
        lib/phoenix_prerender_manifest.ex
        lib/phoenix_prerender_page_cache.ex
        lib/phoenix_prerender_path.ex
        lib/phoenix_prerender_plug.ex
        lib/phoenix_prerender_regenerator.ex
        lib/phoenix_prerender_renderer.ex
        lib/phoenix_prerender_route.ex
        lib/phoenix_prerender_telemetry.ex
        lib/mix
        LICENSE
        README.md
        CHANGELOG.md
        mix.exs
        .formatter.exs
      )
    ]
  end

  defp docs do
    [
      main: "PhoenixPrerender",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        Core: [
          PhoenixPrerender,
          PhoenixPrerender.Plug,
          PhoenixPrerender.Generator,
          PhoenixPrerender.Renderer
        ],
        "Route Discovery": [
          PhoenixPrerender.Route,
          PhoenixPrerender.Path,
          PhoenixPrerender.Manifest
        ],
        "Caching & ISR": [
          PhoenixPrerender.PageCache,
          PhoenixPrerender.Regenerator,
          PhoenixPrerender.Cluster
        ],
        Observability: [
          PhoenixPrerender.Telemetry
        ],
        "Mix Tasks": [
          Mix.Tasks.Phoenix.Prerender
        ]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"],
      verify: &verify/1
    ]
  end

  defp verify(_) do
    steps = [
      {"compile --warnings-as-errors", :dev},
      {"format --check-formatted", :dev},
      {"credo --strict", :dev},
      # {"dialyzer", :dev},
      {"test --cover", :test},
      {"docs --warnings-as-errors", :dev}
    ]

    Enum.each(steps, fn {task, env} ->
      Mix.shell().info([:bright, "==> mix #{task}", :reset])

      {_, exit_code} =
        System.cmd("mix", String.split(task),
          env: [{"MIX_ENV", to_string(env)}],
          into: IO.stream()
        )

      if exit_code != 0 do
        Mix.raise("mix #{task} failed (exit code #{exit_code})")
      end
    end)

    Mix.shell().info([:green, :bright, "\nAll verification checks passed!", :reset])
  end
end
