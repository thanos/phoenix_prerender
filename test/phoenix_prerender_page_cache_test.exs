defmodule PhoenixPrerender.PageCacheTest do
  use ExUnit.Case, async: false

  alias PhoenixPrerender.PageCache

  setup do
    start_supervised!(PageCache)
    :ok
  end

  describe "get/1 and put/2" do
    test "stores and retrieves pages" do
      PageCache.put("/about", "<html>About</html>")
      assert {:ok, "<html>About</html>", _meta} = PageCache.get("/about")
    end

    test "returns :miss for uncached paths" do
      assert :miss = PageCache.get("/nonexistent")
    end

    test "stores metadata" do
      PageCache.put("/about", "<html>About</html>", %{custom: "data"})
      {:ok, _html, meta} = PageCache.get("/about")
      assert meta.custom == "data"
      assert is_integer(meta.cached_at)
    end
  end

  describe "delete/1" do
    test "removes cached page" do
      PageCache.put("/about", "<html>About</html>")
      PageCache.delete("/about")
      assert :miss = PageCache.get("/about")
    end

    test "does not raise for missing key" do
      PageCache.delete("/nonexistent")
    end
  end

  describe "clear/0" do
    test "removes all cached pages" do
      PageCache.put("/a", "a")
      PageCache.put("/b", "b")
      PageCache.clear()

      assert :miss = PageCache.get("/a")
      assert :miss = PageCache.get("/b")
    end
  end

  describe "size/0" do
    test "returns number of cached pages" do
      assert PageCache.size() == 0

      PageCache.put("/a", "a")
      PageCache.put("/b", "b")
      assert PageCache.size() == 2
    end
  end

  describe "stale?/2" do
    test "returns true for missing pages" do
      assert PageCache.stale?("/missing", 300)
    end

    test "returns false for recently cached pages" do
      PageCache.put("/about", "<html>About</html>")
      refute PageCache.stale?("/about", 300)
    end
  end

  describe "prewarm" do
    setup do
      # Stop the default PageCache started by the outer setup
      stop_supervised!(PageCache)
      :ok
    end

    test "prewarming loads manifest pages into cache" do
      output_path = "test/tmp/prewarm_test"
      File.rm_rf!(output_path)
      File.mkdir_p!(output_path)

      # Generate pages to create manifest and files
      {:ok, _results} =
        PhoenixPrerender.Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: output_path,
          paths: ["/about", "/docs"]
        )

      # Start PageCache with prewarm enabled
      start_supervised!({PageCache, prewarm: true, output_path: output_path})

      # Give prewarm a moment to complete via handle_continue
      Process.sleep(100)

      assert {:ok, html, meta} = PageCache.get("/about")
      assert is_binary(html)
      assert html =~ "About"
      assert meta.prewarmed == true

      assert {:ok, _html, _meta} = PageCache.get("/docs")

      File.rm_rf!(output_path)
    end

    test "prewarm does not crash when manifest is missing" do
      start_supervised!({PageCache, prewarm: true, output_path: "test/tmp/nonexistent"})

      # Give handle_continue a moment
      Process.sleep(50)

      assert PageCache.size() == 0
    end

    test "prewarm is off by default" do
      start_supervised!(PageCache)
      Process.sleep(50)
      assert PageCache.size() == 0
    end
  end
end
