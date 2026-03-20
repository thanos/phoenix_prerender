defmodule PhoenixPrerenderWeb.ChangelogLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <div>Changelog</div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
