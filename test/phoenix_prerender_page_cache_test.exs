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
end
