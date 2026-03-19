defmodule PhoenixPrerender.GenerationStamp do
  @moduledoc false

  # File-based generation stamp for cross-process cache invalidation.
  #
  # When `mix phoenix.prerender` writes new files, it also writes a stamp file
  # containing a unique ID. The plug checks this stamp on each request and
  # clears the ETS page cache when it detects a new generation.

  @stamp_file ".generation_stamp"

  @doc """
  Writes a new generation stamp to the output directory.
  """
  @spec write!(String.t()) :: :ok
  def write!(output_path) do
    stamp = System.system_time(:nanosecond) |> Integer.to_string()
    path = Path.join(output_path, @stamp_file)
    File.write!(path, stamp)
  end

  @doc """
  Reads the current generation stamp, or `nil` if none exists.
  """
  @spec read(String.t()) :: String.t() | nil
  def read(output_path) do
    path = Path.join(output_path, @stamp_file)

    case File.read(path) do
      {:ok, stamp} -> stamp
      {:error, _} -> nil
    end
  end
end
