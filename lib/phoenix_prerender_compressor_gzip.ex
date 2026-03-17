defmodule PhoenixPrerender.Compressor.Gzip do
  @moduledoc """
  Built-in gzip compressor using Erlang's `:zlib` module.

  This compressor requires no external NIF dependencies and is suitable
  for most use cases. It produces `.gz` files alongside the original
  HTML files.

  ## Usage

      config :phoenix_prerender,
        compressors: [PhoenixPrerender.Compressor.Gzip]

  ## Example

      {:ok, compressed} = PhoenixPrerender.Compressor.Gzip.compress("<html>Hello</html>")
      :zlib.gunzip(compressed)
      #=> "<html>Hello</html>"
  """

  @behaviour PhoenixPrerender.Compressor

  @doc """
  Compresses the given content using gzip.

  Uses `:zlib.gzip/1` from the Erlang standard library.

  ## Examples

      {:ok, compressed} = PhoenixPrerender.Compressor.Gzip.compress("hello")
      :zlib.gunzip(compressed)
      #=> "hello"
  """
  @impl true
  @spec compress(binary()) :: {:ok, binary()} | {:error, term()}
  def compress(content) do
    {:ok, :zlib.gzip(content)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Returns the file extension for gzip files.

  ## Examples

      iex> PhoenixPrerender.Compressor.Gzip.extension()
      ".gz"
  """
  @impl true
  @spec extension() :: String.t()
  def extension, do: ".gz"
end
