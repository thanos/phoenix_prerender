defmodule Mix.Tasks.Phx.Prerender do
  @moduledoc """
  Alias for `mix phoenix.prerender`.

  See `Mix.Tasks.Phoenix.Prerender` for full documentation.
  """

  use Mix.Task

  @shortdoc "Generate static HTML from prerendered Phoenix routes"

  @impl true
  defdelegate run(args), to: Mix.Tasks.Phoenix.Prerender
end
