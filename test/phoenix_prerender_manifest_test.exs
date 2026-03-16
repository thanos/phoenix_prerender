defmodule PhoenixPrerender.ManifestTest do
  use ExUnit.Case, async: false

  alias PhoenixPrerender.Manifest

  @output_path "test/tmp/manifest_test"

  setup do
    File.rm_rf!(@output_path)
    File.mkdir_p!(@output_path)
    on_exit(fn -> File.rm_rf!(@output_path) end)
    :ok
  end

  defp sample_entries do
    [
      %{
        path: "/about",
        file: "#{@output_path}/about/index.html",
        size: 1234,
        checksum: "abc123",
        generated_at: "2024-01-01T00:00:00Z"
      },
      %{
        path: "/docs",
        file: "#{@output_path}/docs/index.html",
        size: 5678,
        checksum: "def456",
        generated_at: "2024-01-01T00:00:00Z"
      }
    ]
  end

  describe "write/2 and read/1" do
    test "writes and reads manifest" do
      Manifest.write(sample_entries(), @output_path)

      {:ok, manifest} = Manifest.read(@output_path)

      assert is_binary(manifest["generated_at"])
      assert length(manifest["pages"]) == 2

      about = Enum.find(manifest["pages"], &(&1["route"] == "/about"))
      assert about["size"] == 1234
      assert about["checksum"] == "abc123"
    end

    test "returns error when manifest does not exist" do
      assert {:error, :enoent} = Manifest.read("nonexistent/path")
    end
  end

  describe "write_sitemap/3" do
    test "writes valid sitemap XML" do
      Manifest.write_sitemap(sample_entries(), @output_path)

      sitemap = File.read!(Path.join(@output_path, "sitemap.xml"))
      assert sitemap =~ "<?xml version=\"1.0\""
      assert sitemap =~ "<urlset"
      assert sitemap =~ "/about"
      assert sitemap =~ "/docs"
    end

    test "uses custom base URL" do
      Manifest.write_sitemap(sample_entries(), @output_path, base_url: "https://mysite.com")

      sitemap = File.read!(Path.join(@output_path, "sitemap.xml"))
      assert sitemap =~ "https://mysite.com/about"
    end
  end

  describe "lookup/2" do
    test "finds page by route" do
      manifest = %{
        "pages" => [
          %{"route" => "/about", "checksum" => "abc"},
          %{"route" => "/docs", "checksum" => "def"}
        ]
      }

      result = Manifest.lookup(manifest, "/about")
      assert result["checksum"] == "abc"
    end

    test "returns nil for missing route" do
      manifest = %{"pages" => [%{"route" => "/about"}]}
      assert Manifest.lookup(manifest, "/missing") == nil
    end

    test "returns nil for invalid manifest" do
      assert Manifest.lookup(%{}, "/about") == nil
    end
  end
end
