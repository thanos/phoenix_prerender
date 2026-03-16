defmodule PhoenixPrerender.PathTest do
  use ExUnit.Case, async: true

  alias PhoenixPrerender.Path

  describe "to_file_path/2 with :dir_index" do
    test "maps root to index.html" do
      assert Path.to_file_path("/", :dir_index) == "index.html"
    end

    test "maps single segment to dir/index.html" do
      assert Path.to_file_path("/about", :dir_index) == "about/index.html"
    end

    test "maps nested path to nested dir/index.html" do
      assert Path.to_file_path("/docs/terms", :dir_index) == "docs/terms/index.html"
    end

    test "maps deeply nested path" do
      assert Path.to_file_path("/a/b/c/d", :dir_index) == "a/b/c/d/index.html"
    end
  end

  describe "to_file_path/2 with :file" do
    test "maps root to index.html" do
      assert Path.to_file_path("/", :file) == "index.html"
    end

    test "maps single segment to file.html" do
      assert Path.to_file_path("/about", :file) == "about.html"
    end

    test "maps nested path" do
      assert Path.to_file_path("/docs/terms", :file) == "docs/terms.html"
    end
  end

  describe "full_output_path/3" do
    test "joins output dir with file path" do
      assert Path.full_output_path("/about", "priv/static/prerendered", :dir_index) ==
               "priv/static/prerendered/about/index.html"
    end

    test "handles root path" do
      assert Path.full_output_path("/", "priv/static/prerendered", :dir_index) ==
               "priv/static/prerendered/index.html"
    end
  end

  describe "normalize/1" do
    test "preserves root" do
      assert Path.normalize("/") == "/"
    end

    test "strips trailing slash" do
      assert Path.normalize("/about/") == "/about"
    end

    test "strips query string" do
      assert Path.normalize("/about?foo=bar") == "/about"
    end

    test "handles path with trailing slash and query" do
      assert Path.normalize("/about/?foo=bar") == "/about"
    end

    test "returns root for empty path after normalization" do
      assert Path.normalize("///") == "/"
    end
  end

  describe "safe?/1" do
    test "allows normal paths" do
      assert Path.safe?("/about")
      assert Path.safe?("/docs/terms")
      assert Path.safe?("/a/b/c")
    end

    test "rejects path traversal" do
      refute Path.safe?("/about/../etc/passwd")
      refute Path.safe?("/../secret")
      refute Path.safe?("/about/../../secret")
    end
  end
end
