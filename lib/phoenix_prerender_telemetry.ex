defmodule PhoenixPrerender.Telemetry do
  @moduledoc """
  Telemetry events emitted by PhoenixPrerender.

  ## Events

  * `[:phoenix_prerender, :generate]` - Emitted after a full generation run.

    Measurements: `%{duration: integer, count: integer, successes: integer, failures: integer}`
    Metadata: `%{output_path: String.t()}`

  * `[:phoenix_prerender, :render]` - Emitted after rendering a single page.

    Measurements: `%{duration: integer}`
    Metadata: `%{path: String.t(), status: integer}`

  * `[:phoenix_prerender, :serve]` - Emitted when serving a prerendered page.

    Measurements: `%{duration: integer}`
    Metadata: `%{path: String.t(), source: :disk | :cache}`

  * `[:phoenix_prerender, :regenerate]` - Emitted after ISR regeneration.

    Measurements: `%{duration: integer}`
    Metadata: `%{path: String.t(), result: :ok | :error}`

  All durations are in native time units. Use `System.convert_time_unit/3`
  to convert to milliseconds or other units.
  """

  @doc """
  Returns the list of telemetry event names emitted by PhoenixPrerender.
  """
  @spec events() :: [list()]
  def events do
    [
      [:phoenix_prerender, :generate],
      [:phoenix_prerender, :render],
      [:phoenix_prerender, :serve],
      [:phoenix_prerender, :regenerate]
    ]
  end

  @doc """
  Attaches a simple logging handler for all PhoenixPrerender telemetry events.

  Useful for development and debugging.
  """
  @spec attach_default_logger() :: :ok
  def attach_default_logger do
    events()
    |> Enum.each(fn event ->
      :telemetry.attach(
        "phoenix-prerender-logger-#{Enum.join(event, "-")}",
        event,
        &handle_event/4,
        nil
      )
    end)
  end

  defp handle_event(event, measurements, metadata, _config) do
    require Logger

    Logger.debug(
      "PhoenixPrerender telemetry: #{inspect(event)} " <>
        "measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )
  end
end
