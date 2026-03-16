defmodule PhoenixPrerender.RegeneratorTest do
  use PhoenixPrerenderWeb.ConnCase, async: false

  alias PhoenixPrerender.Regenerator

  @output_path "test/tmp/regenerator_test"

  setup do
    File.rm_rf!(@output_path)
    File.mkdir_p!(@output_path)
    start_supervised!({Regenerator, endpoint: PhoenixPrerenderWeb.Endpoint})
    on_exit(fn -> File.rm_rf!(@output_path) end)
    :ok
  end

  describe "regenerate/4" do
    test "regenerates a page and writes to disk" do
      assert :ok =
               Regenerator.regenerate(
                 "/about",
                 PhoenixPrerenderWeb.Endpoint,
                 @output_path,
                 :dir_index
               )

      file_path = Path.join(@output_path, "about/index.html")
      assert File.exists?(file_path)

      content = File.read!(file_path)
      assert content =~ "About"
    end

    test "returns error for invalid path" do
      assert {:error, _} =
               Regenerator.regenerate(
                 "/nonexistent-page-xyz",
                 PhoenixPrerenderWeb.Endpoint,
                 @output_path,
                 :dir_index
               )
    end
  end

  describe "file_stale?/1" do
    test "returns true for missing files" do
      assert Regenerator.file_stale?("/nonexistent/file.html")
    end

    test "returns false for recently created files" do
      path = Path.join(@output_path, "fresh.html")
      File.write!(path, "content")
      refute Regenerator.file_stale?(path)
    end
  end

  describe "maybe_regenerate/2" do
    test "starts regeneration and prevents duplicate" do
      assert :ok = Regenerator.maybe_regenerate("/about", PhoenixPrerenderWeb.Endpoint)

      assert :already_regenerating =
               Regenerator.maybe_regenerate("/about", PhoenixPrerenderWeb.Endpoint)
    end
  end

  describe "isr_enabled?/0" do
    test "returns configured value" do
      refute Regenerator.isr_enabled?()
    end
  end

  describe "revalidate_interval/0" do
    test "returns configured value" do
      assert is_integer(Regenerator.revalidate_interval())
      assert Regenerator.revalidate_interval() > 0
    end
  end
end
