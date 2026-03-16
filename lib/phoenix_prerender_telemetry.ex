defmodule PhoenixPrerender.Telemetry do
  @moduledoc """
  Telemetry events emitted by PhoenixPrerender.

  PhoenixPrerender emits `:telemetry` events at key points in the
  prerendering lifecycle: generation, rendering, serving, and ISR
  regeneration. You can attach handlers to these events to collect
  metrics, trigger alerts, or log activity.

  ## Events

  ### `[:phoenix_prerender, :generate]`

  Emitted once after a full generation run completes (e.g., via
  `mix phoenix.prerender` or `PhoenixPrerender.Generator.generate/1`).

  | Key | Type | Description |
  |---|---|---|
  | **Measurements** | | |
  | `:duration` | `integer` | Wall-clock time in native units |
  | `:count` | `integer` | Total pages attempted |
  | `:successes` | `integer` | Pages generated successfully |
  | `:failures` | `integer` | Pages that failed to render |
  | **Metadata** | | |
  | `:output_path` | `String.t()` | Directory where files were written |

  ### `[:phoenix_prerender, :render]`

  Emitted after rendering a single page through the endpoint pipeline.

  | Key | Type | Description |
  |---|---|---|
  | **Measurements** | | |
  | `:duration` | `integer` | Time spent rendering in native units |
  | **Metadata** | | |
  | `:path` | `String.t()` | URL path that was rendered |
  | `:status` | `integer` | HTTP status code of the response |

  ### `[:phoenix_prerender, :serve]`

  Emitted when `PhoenixPrerender.Plug` serves a prerendered page.

  | Key | Type | Description |
  |---|---|---|
  | **Measurements** | | |
  | `:duration` | `integer` | Time to send the file in native units |
  | **Metadata** | | |
  | `:path` | `String.t()` | Requested URL path |
  | `:source` | `:disk \| :cache` | Where the content was served from |

  ### `[:phoenix_prerender, :regenerate]`

  Emitted after an ISR regeneration attempt for a single page.

  | Key | Type | Description |
  |---|---|---|
  | **Measurements** | | |
  | `:duration` | `integer` | Regeneration time in native units |
  | **Metadata** | | |
  | `:path` | `String.t()` | URL path that was regenerated |
  | `:result` | `:ok \| :error` | Whether regeneration succeeded |

  ## Time Units

  All durations are in native time units. Convert them with
  `System.convert_time_unit/3`:

      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

  ## Attaching Handlers

  Attach your own handler to any event:

      :telemetry.attach(
        "my-handler",
        [:phoenix_prerender, :serve],
        fn event, measurements, metadata, _config ->
          Logger.info("Served \#{metadata.path} in \#{measurements.duration}ns")
        end,
        nil
      )

  Or use `attach_default_logger/0` for quick debug logging of all events:

      PhoenixPrerender.Telemetry.attach_default_logger()

  ## Integration with Telemetry.Metrics

  Use the event names with `Telemetry.Metrics` in your telemetry module:

      def metrics do
        [
          summary("phoenix_prerender.generate.duration",
            unit: {:native, :millisecond}),
          counter("phoenix_prerender.serve.duration"),
          summary("phoenix_prerender.render.duration",
            unit: {:native, :millisecond},
            tags: [:status]),
          counter("phoenix_prerender.regenerate.duration",
            tags: [:result])
        ]
      end
  """

  @doc """
  Returns the list of all telemetry event names emitted by PhoenixPrerender.

  Useful for attaching handlers or configuring metrics reporters.

  ## Examples

      iex> PhoenixPrerender.Telemetry.events()
      [
        [:phoenix_prerender, :generate],
        [:phoenix_prerender, :render],
        [:phoenix_prerender, :serve],
        [:phoenix_prerender, :regenerate]
      ]
  """
  @spec events() :: [[atom()]]
  def events do
    [
      [:phoenix_prerender, :generate],
      [:phoenix_prerender, :render],
      [:phoenix_prerender, :serve],
      [:phoenix_prerender, :regenerate]
    ]
  end

  @doc """
  Attaches a default Logger-based handler to all PhoenixPrerender telemetry events.

  Each event is logged at the `:debug` level with the event name,
  measurements, and metadata. This is intended for development and
  debugging -- in production, attach your own handlers or use
  `Telemetry.Metrics`.

  The handlers are attached with IDs of the form
  `"phoenix-prerender-logger-<event>"`, so they can be detached with
  `:telemetry.detach/1` if needed.

  ## Examples

      PhoenixPrerender.Telemetry.attach_default_logger()
      # Now all PhoenixPrerender events will be logged at :debug level

      # To detach later:
      :telemetry.detach("phoenix-prerender-logger-phoenix_prerender-serve")
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
