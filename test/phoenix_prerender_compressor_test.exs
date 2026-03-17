defmodule PhoenixPrerender.CompressorTest do
  use ExUnit.Case, async: false

  alias PhoenixPrerender.Compressor

  doctest PhoenixPrerender.Compressor

  setup do
    original = Application.get_env(:phoenix_prerender, :compressors)

    on_exit(fn ->
      if original do
        Application.put_env(:phoenix_prerender, :compressors, original)
      else
        Application.delete_env(:phoenix_prerender, :compressors)
      end
    end)

    :ok
  end

  describe "compress_all/1" do
    test "returns empty list when no compressors configured" do
      Application.put_env(:phoenix_prerender, :compressors, [])
      assert Compressor.compress_all("hello") == []
    end

    test "returns compressed results for configured compressors" do
      Application.put_env(:phoenix_prerender, :compressors, [PhoenixPrerender.Compressor.Gzip])
      results = Compressor.compress_all("<html>Hello World</html>")

      assert [{".gz", compressed}] = results
      assert is_binary(compressed)
      assert :zlib.gunzip(compressed) == "<html>Hello World</html>"
    end

    test "skips failing compressors with a warning" do
      defmodule FailingCompressor do
        @behaviour PhoenixPrerender.Compressor
        def compress(_content), do: {:error, :always_fails}
        def extension, do: ".fail"
      end

      Application.put_env(:phoenix_prerender, :compressors, [
        FailingCompressor,
        PhoenixPrerender.Compressor.Gzip
      ])

      results = Compressor.compress_all("hello")

      # Only gzip should succeed
      assert [{".gz", _compressed}] = results
    end

    test "handles multiple compressors" do
      defmodule IdentityCompressor do
        @behaviour PhoenixPrerender.Compressor
        def compress(content), do: {:ok, content}
        def extension, do: ".identity"
      end

      Application.put_env(:phoenix_prerender, :compressors, [
        PhoenixPrerender.Compressor.Gzip,
        IdentityCompressor
      ])

      results = Compressor.compress_all("hello")
      assert length(results) == 2
      extensions = Enum.map(results, &elem(&1, 0))
      assert ".gz" in extensions
      assert ".identity" in extensions
    end
  end

  describe "compressors/0" do
    test "returns configured compressors" do
      Application.put_env(:phoenix_prerender, :compressors, [PhoenixPrerender.Compressor.Gzip])
      assert Compressor.compressors() == [PhoenixPrerender.Compressor.Gzip]
    end

    test "defaults to empty list" do
      Application.delete_env(:phoenix_prerender, :compressors)
      assert Compressor.compressors() == []
    end
  end
end
