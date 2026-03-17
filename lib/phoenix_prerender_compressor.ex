defmodule PhoenixPrerender.Compressor do
  @moduledoc """
  Behaviour and orchestrator for pluggable pre-compression of prerendered pages.

  Pre-compression generates compressed variants of HTML files at build time
  (e.g., `about/index.html.gz`, `about/index.html.br`), so the serving plug
  can send them directly without on-the-fly compression overhead.

  ## Pluggable Design

  Compression is pluggable with no mandatory NIF dependencies. Users swap
  implementations via a behaviour, similar to `config :phoenix, :json_library`.

  A built-in gzip compressor (`PhoenixPrerender.Compressor.Gzip`) uses
  Erlang's `:zlib` module and requires no external dependencies.

  ## Configuration

      config :phoenix_prerender,
        compressors: []  # default: empty (no pre-compression)

  To enable gzip pre-compression:

      config :phoenix_prerender,
        compressors: [PhoenixPrerender.Compressor.Gzip]

  ## Implementing a Custom Compressor

  Implement the `PhoenixPrerender.Compressor` behaviour:

      defmodule MyApp.BrotliCompressor do
        @behaviour PhoenixPrerender.Compressor

        @impl true
        def compress(content) do
          case :brotli.encode(content) do
            {:ok, compressed} -> {:ok, compressed}
            error -> {:error, error}
          end
        end

        @impl true
        def extension, do: ".br"
      end

  Then add it to your config:

      config :phoenix_prerender,
        compressors: [PhoenixPrerender.Compressor.Gzip, MyApp.BrotliCompressor]
  """

  require Logger

  @doc """
  Compresses the given content and returns the compressed binary.

  Must return `{:ok, compressed_binary}` on success, or
  `{:error, reason}` on failure.
  """
  @callback compress(content :: binary()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Returns the file extension for the compressed format (e.g., `".gz"`, `".br"`).
  """
  @callback extension() :: String.t()

  @doc """
  Compresses the given content using all configured compressors.

  Returns a list of `{extension, compressed_bytes}` tuples for each
  compressor that succeeded. Failed compressors are logged as warnings
  and skipped (fault-tolerant).

  ## Examples

      # With gzip configured
      [{".gz", compressed}] = PhoenixPrerender.Compressor.compress_all("hello")

      # With no compressors configured
      [] = PhoenixPrerender.Compressor.compress_all("hello")
  """
  @spec compress_all(binary()) :: [{String.t(), binary()}]
  def compress_all(content) do
    compressors()
    |> Enum.reduce([], fn compressor, acc ->
      case compressor.compress(content) do
        {:ok, compressed} ->
          [{compressor.extension(), compressed} | acc]

        {:error, reason} ->
          Logger.warning(
            "PhoenixPrerender: Compressor #{inspect(compressor)} failed: #{inspect(reason)}"
          )

          acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Returns the list of configured compressor modules.

  ## Examples

      iex> PhoenixPrerender.Compressor.compressors()
      []
  """
  @spec compressors() :: [module()]
  def compressors do
    Application.get_env(:phoenix_prerender, :compressors, [])
  end
end
