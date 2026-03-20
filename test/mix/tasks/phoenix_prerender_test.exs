defmodule Mix.Tasks.Phoenix.PrerenderTest do
  use ExUnit.Case, async: false

  @output_path "test/tmp/mix_task_test"

  setup do
    File.rm_rf!(@output_path)
    File.mkdir_p!(@output_path)
    on_exit(fn -> File.rm_rf!(@output_path) end)
    :ok
  end

  describe "run/1" do
    test "generates prerendered pages with explicit modules" do
      Mix.Tasks.Phoenix.Prerender.run([
        "--router",
        "PhoenixPrerenderWeb.Router",
        "--endpoint",
        "PhoenixPrerenderWeb.Endpoint",
        "--output",
        @output_path
      ])

      # Should have generated files for prerender-marked routes
      assert File.exists?(Path.join(@output_path, "about/index.html"))
      assert File.exists?(Path.join(@output_path, "docs/index.html"))
      assert File.exists?(Path.join(@output_path, "docs/terms/index.html"))

      # manifest.json should be written
      assert File.exists?(Path.join(@output_path, "manifest.json"))
    end

    test "generates with --style file" do
      Mix.Tasks.Phoenix.Prerender.run([
        "--router",
        "PhoenixPrerenderWeb.Router",
        "--endpoint",
        "PhoenixPrerenderWeb.Endpoint",
        "--output",
        @output_path,
        "--style",
        "file"
      ])

      assert File.exists?(Path.join(@output_path, "about.html"))
    end

    test "generates specific paths with --path" do
      Mix.Tasks.Phoenix.Prerender.run([
        "--router",
        "PhoenixPrerenderWeb.Router",
        "--endpoint",
        "PhoenixPrerenderWeb.Endpoint",
        "--output",
        @output_path,
        "--path",
        "/about"
      ])

      assert File.exists?(Path.join(@output_path, "about/index.html"))
      # docs should NOT have been generated since we only requested /about
      refute File.exists?(Path.join(@output_path, "docs/index.html"))
    end

    test "generates with --concurrency" do
      Mix.Tasks.Phoenix.Prerender.run([
        "--router",
        "PhoenixPrerenderWeb.Router",
        "--endpoint",
        "PhoenixPrerenderWeb.Endpoint",
        "--output",
        @output_path,
        "--concurrency",
        "1"
      ])

      assert File.exists?(Path.join(@output_path, "about/index.html"))
    end

    test "raises with invalid --style" do
      assert_raise Mix.Error, ~r/Invalid URL style/, fn ->
        Mix.Tasks.Phoenix.Prerender.run([
          "--router",
          "PhoenixPrerenderWeb.Router",
          "--endpoint",
          "PhoenixPrerenderWeb.Endpoint",
          "--output",
          @output_path,
          "--style",
          "bad"
        ])
      end
    end

    test "raises when router cannot be resolved" do
      assert_raise Mix.Error, ~r/Could not resolve router/, fn ->
        Mix.Tasks.Phoenix.Prerender.run([
          "--router",
          "NonExistent.Router",
          "--endpoint",
          "PhoenixPrerenderWeb.Endpoint",
          "--output",
          @output_path
        ])
      end
    end

    test "raises when endpoint cannot be resolved" do
      assert_raise Mix.Error, ~r/Could not resolve endpoint/, fn ->
        Mix.Tasks.Phoenix.Prerender.run([
          "--router",
          "PhoenixPrerenderWeb.Router",
          "--endpoint",
          "NonExistent.Endpoint",
          "--output",
          @output_path
        ])
      end
    end
  end
end
