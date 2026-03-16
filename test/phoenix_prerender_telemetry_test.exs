defmodule PhoenixPrerender.TelemetryTest do
  use ExUnit.Case, async: true

  alias PhoenixPrerender.Telemetry

  doctest PhoenixPrerender.Telemetry

  describe "events/0" do
    test "returns list of telemetry event names" do
      events = Telemetry.events()

      assert [:phoenix_prerender, :generate] in events
      assert [:phoenix_prerender, :render] in events
      assert [:phoenix_prerender, :serve] in events
      assert [:phoenix_prerender, :regenerate] in events
    end
  end

  describe "attach_default_logger/0" do
    test "attaches handlers without error" do
      assert :ok = Telemetry.attach_default_logger()
    end
  end
end
