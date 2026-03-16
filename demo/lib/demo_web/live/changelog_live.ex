defmodule DemoWeb.ChangelogLive do
  @moduledoc """
  A prerendered LiveView route demonstrating that LiveView pages
  can be statically generated via HTTP rendering.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    entries = [
      %{version: "0.3.0", date: "2024-03-01", description: "Distributed ISR via :global.trans"},
      %{version: "0.2.0", date: "2024-02-01", description: "Incremental static regeneration"},
      %{version: "0.1.0", date: "2024-01-01", description: "Initial static generation"}
    ]

    {:ok, assign(socket, entries: entries)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Changelog</h1>
    <p>This is a prerendered LiveView page.</p>
    <div id="entries">
      <div :for={entry <- @entries} id={"entry-#{entry.version}"} style="margin-bottom: 1rem;">
        <h3>{entry.version} - {entry.date}</h3>
        <p>{entry.description}</p>
      </div>
    </div>
    """
  end
end
