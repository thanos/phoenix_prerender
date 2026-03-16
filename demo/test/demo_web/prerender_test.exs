defmodule DemoWeb.PrerenderTest do
  use DemoWeb.ConnCase

  alias PhoenixPrerender.Route

  test "discovers all prerendered routes" do
    paths = Route.paths(DemoWeb.Router)

    assert "/about" in paths
    assert "/features" in paths
    assert "/docs" in paths
    assert "/docs/getting-started" in paths
    assert "/docs/terms" in paths
    assert "/changelog" in paths
    assert "/status" in paths
  end

  test "excludes non-prerendered routes" do
    paths = Route.paths(DemoWeb.Router)

    refute "/" in paths
    refute "/contact" in paths
    refute "/dashboard" in paths
  end

  test "generates prerendered pages" do
    output_path = "test/tmp/demo_prerendered"
    File.rm_rf!(output_path)

    on_exit(fn -> File.rm_rf!(output_path) end)

    {:ok, results} =
      PhoenixPrerender.Generator.generate(
        router: DemoWeb.Router,
        endpoint: DemoWeb.Endpoint,
        output_path: output_path,
        url_style: :dir_index
      )

    successes = Enum.filter(results, &(&1.status == :ok))
    assert length(successes) >= 7

    assert File.exists?(Path.join(output_path, "about/index.html"))
    assert File.exists?(Path.join(output_path, "features/index.html"))
    assert File.exists?(Path.join(output_path, "docs/index.html"))
    assert File.exists?(Path.join(output_path, "docs/getting-started/index.html"))
    assert File.exists?(Path.join(output_path, "docs/terms/index.html"))
    assert File.exists?(Path.join(output_path, "changelog/index.html"))
    assert File.exists?(Path.join(output_path, "status/index.html"))
    assert File.exists?(Path.join(output_path, "manifest.json"))
    assert File.exists?(Path.join(output_path, "sitemap.xml"))
  end
end
