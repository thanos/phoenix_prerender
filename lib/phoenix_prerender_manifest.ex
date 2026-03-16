defmodule PhoenixPrerender.Manifest do
  @moduledoc """
  Manages the manifest file and sitemap for prerendered pages.

  The manifest tracks all generated pages with their metadata,
  including route, output file, generation time, and checksum.
  """

  @manifest_filename "manifest.json"
  @sitemap_filename "sitemap.xml"

  @doc """
  Writes a manifest.json file containing metadata for all generated pages.
  """
  @spec write([map()], String.t()) :: :ok
  def write(entries, output_path) do
    manifest = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      pages:
        Enum.map(entries, fn entry ->
          %{
            route: entry.path,
            file: entry.file,
            size: entry.size,
            checksum: entry.checksum,
            generated_at: entry.generated_at
          }
        end)
    }

    path = Path.join(output_path, @manifest_filename)
    json = Jason.encode!(manifest, pretty: true)
    PhoenixPrerender.Generator.write_atomic!(path, json)
  end

  @doc """
  Reads and parses the manifest file from the output path.

  Returns `{:ok, manifest}` or `{:error, reason}`.
  """
  @spec read(String.t()) :: {:ok, map()} | {:error, term()}
  def read(output_path) do
    path = Path.join(output_path, @manifest_filename)

    case File.read(path) do
      {:ok, content} -> Jason.decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes a sitemap.xml file listing all prerendered routes.

  ## Options

    * `:base_url` - the base URL for sitemap entries (default: "https://example.com")
  """
  @spec write_sitemap([map()], String.t(), keyword()) :: :ok
  def write_sitemap(entries, output_path, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, base_url())

    xml = build_sitemap(entries, base_url)
    path = Path.join(output_path, @sitemap_filename)
    PhoenixPrerender.Generator.write_atomic!(path, xml)
  end

  defp build_sitemap(entries, base_url) do
    urls =
      entries
      |> Enum.map(fn entry ->
        loc = String.trim_trailing(base_url, "/") <> entry.path
        lastmod = entry.generated_at

        """
          <url>
            <loc>#{escape_xml(loc)}</loc>
            <lastmod>#{lastmod}</lastmod>
          </url>
        """
      end)
      |> Enum.join()

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}</urlset>
    """
  end

  defp escape_xml(string) do
    string
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp base_url do
    Application.get_env(:phoenix_prerender, :base_url, "https://example.com")
  end

  @doc """
  Returns the manifest filename.
  """
  @spec manifest_filename() :: String.t()
  def manifest_filename, do: @manifest_filename

  @doc """
  Looks up a page entry in the manifest by route path.
  """
  @spec lookup(map(), String.t()) :: map() | nil
  def lookup(%{"pages" => pages}, path) do
    Enum.find(pages, fn page -> page["route"] == path end)
  end

  def lookup(_, _), do: nil
end
