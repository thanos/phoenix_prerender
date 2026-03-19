defmodule PhoenixPrerender.Manifest do
  @moduledoc """
  Manages the manifest and sitemap files for prerendered pages.

  After generation, two files are written to the output directory:

    * `manifest.json` -- A JSON file listing every generated page with
      its route, output file path, file size, SHA-256 checksum, and
      generation timestamp.

    * `sitemap.xml` -- A standard XML sitemap listing all prerendered
      URLs, suitable for submission to search engines.

  ## Manifest Format

  The manifest file has this structure:

      {
        "generated_at": "2024-01-15T10:30:00Z",
        "pages": [
          {
            "route": "/about",
            "file": "priv/static/prerendered/about/index.html",
            "size": 4521,
            "checksum": "a1b2c3d4...",
            "generated_at": "2024-01-15T10:30:00Z"
          }
        ]
      }

  ## Sitemap Format

  The sitemap follows the standard sitemaps.org protocol:

      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/about</loc>
          <lastmod>2024-01-15T10:30:00Z</lastmod>
        </url>
      </urlset>
  """

  @manifest_filename "manifest.json"
  @sitemap_filename "sitemap.xml"

  @doc """
  Writes a `manifest.json` file to the output directory.

  The manifest contains metadata for every successfully generated page.
  Each entry includes the route path, output file, file size, content
  checksum, and generation timestamp.

  The file is written atomically via `PhoenixPrerender.Generator.write_atomic!/2`.

  ## Parameters

    * `entries` -- list of successful generation result maps (with
      `:path`, `:file`, `:size`, `:checksum`, `:generated_at` keys)
    * `output_path` -- the output directory

  ## Examples

      entries = [
        %{path: "/about", file: "out/about/index.html", size: 1024,
          checksum: "abc123", generated_at: "2024-01-15T10:30:00Z"}
      ]
      PhoenixPrerender.Manifest.write(entries, "out")
      # Writes out/manifest.json
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
            generated_at: entry.generated_at,
            prerender_mode: to_string(Map.get(entry, :prerender_mode, true)),
            isr: Map.get(entry, :isr, false)
          }
        end)
    }

    path = Path.join(output_path, @manifest_filename)
    json = Jason.encode!(manifest, pretty: true)
    PhoenixPrerender.Generator.write_atomic!(path, json)
  end

  @doc """
  Reads and parses the manifest file from the given output directory.

  Returns `{:ok, manifest}` on success where `manifest` is a decoded
  JSON map with string keys, or `{:error, reason}` if the file does
  not exist or cannot be parsed.

  ## Examples

      {:ok, manifest} = PhoenixPrerender.Manifest.read("priv/static/prerendered")
      manifest["pages"]
      #=> [%{"route" => "/about", "checksum" => "abc123", ...}]

      {:error, :enoent} = PhoenixPrerender.Manifest.read("/nonexistent")
  """
  @spec read(String.t()) :: {:ok, map()} | {:error, term()}
  # sobelow_skip ["Traversal.FileModule"]
  def read(output_path) do
    path = Path.join(output_path, @manifest_filename)

    case File.read(path) do
      {:ok, content} -> Jason.decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes a `sitemap.xml` file to the output directory.

  Generates a standard XML sitemap with `<loc>` and `<lastmod>` entries
  for each prerendered page. The base URL is prepended to each route
  path to form absolute URLs.

  ## Options

    * `:base_url` -- the base URL for sitemap entries
      (default: configured `:base_url` or `"https://example.com"`)

  ## Examples

      entries = [
        %{path: "/about", generated_at: "2024-01-15T10:30:00Z"},
        %{path: "/docs", generated_at: "2024-01-15T10:30:00Z"}
      ]

      PhoenixPrerender.Manifest.write_sitemap(entries, "out",
        base_url: "https://mysite.com"
      )
      # Writes out/sitemap.xml with https://mysite.com/about, etc.
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
      Enum.map_join(entries, fn entry ->
        loc = String.trim_trailing(base_url, "/") <> entry.path
        lastmod = entry.generated_at

        """
          <url>
            <loc>#{escape_xml(loc)}</loc>
            <lastmod>#{lastmod}</lastmod>
          </url>
        """
      end)

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

  ## Examples

      iex> PhoenixPrerender.Manifest.manifest_filename()
      "manifest.json"
  """
  @spec manifest_filename() :: String.t()
  def manifest_filename, do: @manifest_filename

  @doc """
  Looks up a page entry in a parsed manifest by its route path.

  Takes a manifest map (as returned by `read/1`) and a route path
  string. Returns the matching page map or `nil`.

  ## Examples

      manifest = %{"pages" => [
        %{"route" => "/about", "checksum" => "abc"},
        %{"route" => "/docs", "checksum" => "def"}
      ]}

      PhoenixPrerender.Manifest.lookup(manifest, "/about")
      #=> %{"route" => "/about", "checksum" => "abc"}

      PhoenixPrerender.Manifest.lookup(manifest, "/missing")
      #=> nil

      PhoenixPrerender.Manifest.lookup(%{}, "/about")
      #=> nil
  """
  @spec lookup(map(), String.t()) :: map() | nil
  def lookup(%{"pages" => pages}, path) do
    Enum.find(pages, fn page -> page["route"] == path end)
  end

  def lookup(_, _), do: nil
end
