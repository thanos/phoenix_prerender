defmodule PhoenixPrerender.Components do
  @moduledoc """
  LiveView components for prerendered pages.

  Provides the `prerendered/1` component which freezes content at
  prerender time. When LiveView hydrates over WebSocket, the
  prerendered DOM content is preserved — LiveView will not patch it.

  This is useful for ISR pages where some values (like "generated at"
  timestamps) should reflect when the page was rendered, not when the
  browser connected.

  ## Usage

      use Phoenix.Component
      import PhoenixPrerender.Components

      def render(assigns) do
        ~H\"\"\"
        <.prerendered id="gen-time" tag="p" class="font-mono">
          {@generated_at}
        </.prerendered>

        <p>{@current_time}</p>
        \"\"\"
      end

  The first element stays frozen from the prerendered HTML.
  The second updates normally via LiveView.

  ## How it works

  Renders a wrapper element with `phx-update="ignore"`, which tells
  LiveView's client-side JS to skip DOM patching for that node. The
  prerendered HTML value stays in the browser even after LiveView
  connects and re-mounts.
  """

  use Phoenix.Component

  @doc """
  Renders content that is frozen at prerender time.

  LiveView will not update the contents of this element after
  hydration. The value from the prerendered HTML stays visible.

  ## Attributes

    * `id` (required) -- unique DOM id, required by `phx-update="ignore"`
    * `tag` -- the HTML element to render (default: `"span"`)
    * `class` -- optional CSS class(es)

  ## Slots

    * inner block -- the content to freeze

  ## Examples

      <.prerendered id="gen-time">
        {@generated_at}
      </.prerendered>

      <.prerendered id="build-hash" tag="code" class="text-sm">
        {@git_sha}
      </.prerendered>
  """
  attr :id, :string, required: true
  attr :tag, :string, default: "span"
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def prerendered(assigns) do
    ~H"""
    <.dynamic_tag tag_name={@tag} id={@id} phx-update="ignore" class={@class}>
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end
end
