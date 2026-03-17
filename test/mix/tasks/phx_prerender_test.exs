defmodule Mix.Tasks.Phx.PrerenderTest do
  use ExUnit.Case, async: false

  @output_path "test/tmp/phx_task_test"

  setup do
    File.rm_rf!(@output_path)
    File.mkdir_p!(@output_path)
    on_exit(fn -> File.rm_rf!(@output_path) end)
    :ok
  end

  test "delegates to Mix.Tasks.Phoenix.Prerender" do
    Mix.Tasks.Phx.Prerender.run([
      "--router",
      "PhoenixPrerenderWeb.Router",
      "--endpoint",
      "PhoenixPrerenderWeb.Endpoint",
      "--output",
      @output_path
    ])

    assert File.exists?(Path.join(@output_path, "about/index.html"))
  end
end
