defmodule PhoenixPrerender.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import PhoenixPrerender.Components

  describe "prerendered/1" do
    test "renders with phx-update=ignore and required id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.prerendered id="gen-time">
          2026-03-19 19:51:36 UTC
        </.prerendered>
        """)

      assert html =~ ~s(id="gen-time")
      assert html =~ ~s(phx-update="ignore")
      assert html =~ "2026-03-19 19:51:36 UTC"
      assert html =~ "<span"
    end

    test "renders with custom tag" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.prerendered id="build-hash" tag="code">
          abc123
        </.prerendered>
        """)

      assert html =~ "<code"
      assert html =~ ~s(id="build-hash")
      assert html =~ ~s(phx-update="ignore")
      assert html =~ "abc123"
    end

    test "renders with custom class" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.prerendered id="ts" tag="p" class="font-mono text-lg">
          some value
        </.prerendered>
        """)

      assert html =~ ~s(class="font-mono text-lg")
      assert html =~ "<p"
    end

    test "renders assign values in the slot" do
      assigns = %{generated_at: "2026-01-01 00:00:00 UTC"}

      html =
        rendered_to_string(~H"""
        <.prerendered id="gen">
          {@generated_at}
        </.prerendered>
        """)

      assert html =~ "2026-01-01 00:00:00 UTC"
    end
  end
end
