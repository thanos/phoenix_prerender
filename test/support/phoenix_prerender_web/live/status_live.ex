defmodule PhoenixPrerenderWeb.StatusLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <div>Status</div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
