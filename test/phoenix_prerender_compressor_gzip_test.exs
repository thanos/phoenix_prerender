defmodule PhoenixPrerender.Compressor.GzipTest do
  use ExUnit.Case, async: true

  alias PhoenixPrerender.Compressor.Gzip

  doctest PhoenixPrerender.Compressor.Gzip

  describe "compress/1" do
    test "compresses content and round-trips via gunzip" do
      content = "<html><body>Hello World</body></html>"
      assert {:ok, compressed} = Gzip.compress(content)
      assert is_binary(compressed)
      assert byte_size(compressed) > 0
      assert :zlib.gunzip(compressed) == content
    end

    test "compressed output is smaller for larger content" do
      content = String.duplicate("<p>This is a paragraph with repeated content.</p>\n", 100)
      assert {:ok, compressed} = Gzip.compress(content)
      assert byte_size(compressed) < byte_size(content)
    end

    test "handles empty content" do
      assert {:ok, compressed} = Gzip.compress("")
      assert :zlib.gunzip(compressed) == ""
    end

    test "handles binary content" do
      content = <<0, 1, 2, 3, 4, 5>>
      assert {:ok, compressed} = Gzip.compress(content)
      assert :zlib.gunzip(compressed) == content
    end
  end

  describe "extension/0" do
    test "returns .gz" do
      assert Gzip.extension() == ".gz"
    end
  end
end
