defmodule PhoenixPrerender.GeneratorTest do
  use PhoenixPrerenderWeb.ConnCase, async: false

  alias PhoenixPrerender.Generator

  @output_path "test/tmp/prerendered"

  setup do
    File.rm_rf!(@output_path)
    on_exit(fn -> File.rm_rf!(@output_path) end)
    :ok
  end

  describe "generate/1" do
    test "generates HTML files for all prerender routes" do
      {:ok, results} =
        Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: @output_path,
          url_style: :dir_index
        )

      successes = Enum.filter(results, &(&1.status == :ok))
      assert length(successes) >= 3

      assert File.exists?(Path.join(@output_path, "about/index.html"))
      assert File.exists?(Path.join(@output_path, "docs/index.html"))
      assert File.exists?(Path.join(@output_path, "docs/terms/index.html"))
    end

    test "generates with :file url style" do
      {:ok, _results} =
        Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: @output_path,
          url_style: :file
        )

      assert File.exists?(Path.join(@output_path, "about.html"))
    end

    test "generates manifest.json" do
      {:ok, _results} =
        Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: @output_path
        )

      assert File.exists?(Path.join(@output_path, "manifest.json"))

      {:ok, manifest} = PhoenixPrerender.Manifest.read(@output_path)
      assert is_list(manifest["pages"])
      assert length(manifest["pages"]) >= 3
    end

    test "generates sitemap.xml" do
      {:ok, _results} =
        Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: @output_path
        )

      assert File.exists?(Path.join(@output_path, "sitemap.xml"))
      sitemap = File.read!(Path.join(@output_path, "sitemap.xml"))
      assert sitemap =~ "<urlset"
      assert sitemap =~ "/about"
    end

    test "generates only specified paths" do
      {:ok, results} =
        Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: @output_path,
          paths: ["/about"]
        )

      successes = Enum.filter(results, &(&1.status == :ok))
      assert length(successes) == 1
      assert File.exists?(Path.join(@output_path, "about/index.html"))
    end

    test "result entries contain metadata" do
      {:ok, results} =
        Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: @output_path,
          paths: ["/about"]
        )

      [result] = Enum.filter(results, &(&1.status == :ok))
      assert result.path == "/about"
      assert is_binary(result.file)
      assert is_integer(result.size)
      assert is_binary(result.checksum)
      assert is_binary(result.generated_at)
    end
  end

  describe "generate/1 with compressors" do
    setup do
      original = Application.get_env(:phoenix_prerender, :compressors)
      Application.put_env(:phoenix_prerender, :compressors, [PhoenixPrerender.Compressor.Gzip])

      on_exit(fn ->
        if original do
          Application.put_env(:phoenix_prerender, :compressors, original)
        else
          Application.delete_env(:phoenix_prerender, :compressors)
        end
      end)

      :ok
    end

    test "generates .gz files alongside .html when compressors configured" do
      {:ok, results} =
        Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: @output_path,
          url_style: :dir_index,
          paths: ["/about"]
        )

      [result] = Enum.filter(results, &(&1.status == :ok))

      assert [%{extension: ".gz", size: size}] = result.compressed
      assert is_integer(size) and size > 0

      html_path = Path.join(@output_path, "about/index.html")
      gz_path = html_path <> ".gz"
      assert File.exists?(html_path)
      assert File.exists?(gz_path)

      # Verify round-trip
      original = File.read!(html_path)
      compressed = File.read!(gz_path)
      assert :zlib.gunzip(compressed) == original
    end

    test "result does not include :compressed key when no compressors configured" do
      Application.put_env(:phoenix_prerender, :compressors, [])

      {:ok, results} =
        Generator.generate(
          router: PhoenixPrerenderWeb.Router,
          endpoint: PhoenixPrerenderWeb.Endpoint,
          output_path: @output_path,
          paths: ["/about"]
        )

      [result] = Enum.filter(results, &(&1.status == :ok))
      refute Map.has_key?(result, :compressed)
    end
  end

  describe "write_compressed_variants!/2" do
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

    test "writes compressed files alongside the original" do
      Application.put_env(:phoenix_prerender, :compressors, [PhoenixPrerender.Compressor.Gzip])
      path = Path.join(@output_path, "test/compressed.html")
      content = "<html>test</html>"
      Generator.write_atomic!(path, content)
      results = Generator.write_compressed_variants!(path, content)

      assert [%{extension: ".gz", size: _}] = results
      assert File.exists?(path <> ".gz")
      assert :zlib.gunzip(File.read!(path <> ".gz")) == content
    end

    test "returns empty list when no compressors configured" do
      Application.put_env(:phoenix_prerender, :compressors, [])
      path = Path.join(@output_path, "test/no_compress.html")
      Generator.write_atomic!(path, "<html>test</html>")

      assert [] = Generator.write_compressed_variants!(path, "<html>test</html>")
    end
  end

  describe "write_atomic!/2" do
    test "writes file atomically" do
      path = Path.join(@output_path, "test/atomic.html")
      Generator.write_atomic!(path, "<html>test</html>")

      assert File.read!(path) == "<html>test</html>"
      refute File.exists?(path <> ".tmp")
    end

    test "creates parent directories" do
      path = Path.join(@output_path, "deep/nested/dir/file.html")
      Generator.write_atomic!(path, "content")

      assert File.exists?(path)
    end
  end
end
