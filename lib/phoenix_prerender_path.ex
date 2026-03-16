defmodule PhoenixPrerender.Path do
  @moduledoc """
  Maps URL paths to filesystem paths for prerendered HTML files.

  This module handles the conversion between URL paths (as defined in
  your Phoenix router) and the corresponding filesystem paths where
  prerendered HTML files are stored.

  Two URL styles are supported:

    * `:dir_index` (default) -- Each path gets its own directory with an
      `index.html` file. This produces clean URLs when served by most
      web servers and CDNs.

    * `:file` -- Each path maps directly to a `.html` file. More compact
      but may require web server rewrite rules for clean URLs.

  ## Path Mapping Examples

  | URL Path       | `:dir_index`             | `:file`          |
  |----------------|--------------------------|------------------|
  | `/`            | `index.html`             | `index.html`     |
  | `/about`       | `about/index.html`       | `about.html`     |
  | `/docs/terms`  | `docs/terms/index.html`  | `docs/terms.html`|

  The plug and generator use the same mapping logic, so served files
  always correspond to generated files.
  """

  @doc """
  Converts a URL path to a relative filesystem path using the given style.

  The root path `/` always maps to `"index.html"` regardless of style.

  ## Examples

      iex> PhoenixPrerender.Path.to_file_path("/", :dir_index)
      "index.html"

      iex> PhoenixPrerender.Path.to_file_path("/about", :dir_index)
      "about/index.html"

      iex> PhoenixPrerender.Path.to_file_path("/docs/terms", :dir_index)
      "docs/terms/index.html"

      iex> PhoenixPrerender.Path.to_file_path("/about", :file)
      "about.html"

      iex> PhoenixPrerender.Path.to_file_path("/docs/terms", :file)
      "docs/terms.html"

      iex> PhoenixPrerender.Path.to_file_path("/", :file)
      "index.html"

      iex> PhoenixPrerender.Path.to_file_path("/a/b/c", :dir_index)
      "a/b/c/index.html"
  """
  @spec to_file_path(String.t(), :dir_index | :file) :: String.t()
  def to_file_path("/", _style), do: "index.html"

  def to_file_path(path, :dir_index) do
    path
    |> String.trim_leading("/")
    |> Kernel.<>("/index.html")
  end

  def to_file_path(path, :file) do
    path
    |> String.trim_leading("/")
    |> Kernel.<>(".html")
  end

  @doc """
  Converts a URL path to a filesystem path using the application-configured URL style.

  Delegates to `to_file_path/2` with the style from `PhoenixPrerender.url_style/0`.

  ## Examples

      iex> PhoenixPrerender.Path.to_file_path("/about")
      "about/index.html"

      iex> PhoenixPrerender.Path.to_file_path("/")
      "index.html"
  """
  @spec to_file_path(String.t()) :: String.t()
  def to_file_path(path) do
    to_file_path(path, PhoenixPrerender.url_style())
  end

  @doc """
  Returns the full filesystem path for a prerendered file.

  Joins the output directory with the file path derived from `to_file_path/2`.

  ## Examples

      iex> PhoenixPrerender.Path.full_output_path("/about", "priv/static/prerendered", :dir_index)
      "priv/static/prerendered/about/index.html"

      iex> PhoenixPrerender.Path.full_output_path("/", "output", :dir_index)
      "output/index.html"

      iex> PhoenixPrerender.Path.full_output_path("/about", "output", :file)
      "output/about.html"

      iex> PhoenixPrerender.Path.full_output_path("/docs/terms", "out", :dir_index)
      "out/docs/terms/index.html"
  """
  @spec full_output_path(String.t(), String.t(), :dir_index | :file) :: String.t()
  def full_output_path(url_path, output_dir, style) do
    Path.join(output_dir, to_file_path(url_path, style))
  end

  @doc """
  Normalizes a request path for consistent file lookup.

  Strips trailing slashes (except for the root `/`) and removes
  query strings and fragments. This ensures that `/about/`,
  `/about?ref=home`, and `/about` all resolve to the same file.

  ## Examples

      iex> PhoenixPrerender.Path.normalize("/about/")
      "/about"

      iex> PhoenixPrerender.Path.normalize("/about?foo=bar")
      "/about"

      iex> PhoenixPrerender.Path.normalize("/about/?foo=bar")
      "/about"

      iex> PhoenixPrerender.Path.normalize("/")
      "/"

      iex> PhoenixPrerender.Path.normalize("/docs/terms")
      "/docs/terms"
  """
  @spec normalize(String.t()) :: String.t()
  def normalize("/"), do: "/"

  def normalize(path) do
    path
    |> URI.parse()
    |> Map.get(:path, path)
    |> String.trim_trailing("/")
    |> case do
      "" -> "/"
      normalized -> normalized
    end
  end

  @doc """
  Checks whether a path is safe from directory traversal attacks.

  Returns `false` if the path contains `..` sequences, which could
  be used to escape the output directory and access arbitrary files.
  The `PhoenixPrerender.Plug` rejects unsafe paths before attempting
  to serve any file.

  ## Examples

      iex> PhoenixPrerender.Path.safe?("/about")
      true

      iex> PhoenixPrerender.Path.safe?("/docs/terms")
      true

      iex> PhoenixPrerender.Path.safe?("/about/../etc/passwd")
      false

      iex> PhoenixPrerender.Path.safe?("/../secret")
      false

      iex> PhoenixPrerender.Path.safe?("/about/../../secret")
      false
  """
  @spec safe?(String.t()) :: boolean()
  def safe?(path) do
    not String.contains?(path, "..")
  end
end
