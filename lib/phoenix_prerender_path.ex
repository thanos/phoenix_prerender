defmodule PhoenixPrerender.Path do
  @moduledoc """
  Maps URL paths to filesystem paths for prerendered HTML files.

  Supports two URL styles:

  - `:dir_index` (default) - `/about` maps to `about/index.html`
  - `:file` - `/about` maps to `about.html`
  """

  @doc """
  Converts a URL path to a relative filesystem path.

  ## Examples

      iex> PhoenixPrerender.Path.to_file_path("/", :dir_index)
      "index.html"

      iex> PhoenixPrerender.Path.to_file_path("/about", :dir_index)
      "about/index.html"

      iex> PhoenixPrerender.Path.to_file_path("/docs/terms", :dir_index)
      "docs/terms/index.html"

      iex> PhoenixPrerender.Path.to_file_path("/about", :file)
      "about.html"

      iex> PhoenixPrerender.Path.to_file_path("/", :file)
      "index.html"
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
  Converts a URL path to a filesystem path using the configured URL style.

  ## Examples

      iex> PhoenixPrerender.Path.to_file_path("/about")
      "about/index.html"
  """
  @spec to_file_path(String.t()) :: String.t()
  def to_file_path(path) do
    to_file_path(path, PhoenixPrerender.url_style())
  end

  @doc """
  Returns the full output path for a given URL path.

  ## Examples

      iex> PhoenixPrerender.Path.full_output_path("/about", "priv/static/prerendered", :dir_index)
      "priv/static/prerendered/about/index.html"
  """
  @spec full_output_path(String.t(), String.t(), :dir_index | :file) :: String.t()
  def full_output_path(url_path, output_dir, style) do
    Path.join(output_dir, to_file_path(url_path, style))
  end

  @doc """
  Normalizes a request path for file lookup.

  Strips trailing slashes and query strings.

  ## Examples

      iex> PhoenixPrerender.Path.normalize("/about/")
      "/about"

      iex> PhoenixPrerender.Path.normalize("/about?foo=bar")
      "/about"

      iex> PhoenixPrerender.Path.normalize("/")
      "/"
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
  Validates that a path is safe and does not contain traversal sequences.

  ## Examples

      iex> PhoenixPrerender.Path.safe?("/about")
      true

      iex> PhoenixPrerender.Path.safe?("/about/../etc/passwd")
      false

      iex> PhoenixPrerender.Path.safe?("/about/../../secret")
      false
  """
  @spec safe?(String.t()) :: boolean()
  def safe?(path) do
    not String.contains?(path, "..")
  end
end
