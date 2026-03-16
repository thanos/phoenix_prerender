defmodule DemoWeb.ChangelogLive do
  @moduledoc """
  A prerendered LiveView demonstrating static generation + client hydration.

  This page is rendered as static HTML at build time (for instant load and SEO),
  then hydrated via WebSocket for interactivity. The filter buttons only work
  after LiveView connects.
  """
  use DemoWeb, :live_view

  @entries [
    %{
      version: "0.4.0",
      date: "2024-04-01",
      type: :feature,
      description: "Strict paths mode - only serve pages listed in manifest.json"
    },
    %{
      version: "0.3.0",
      date: "2024-03-01",
      type: :feature,
      description: "Distributed ISR via :global.trans/2 and Phoenix PubSub cache invalidation"
    },
    %{
      version: "0.2.1",
      date: "2024-02-15",
      type: :fix,
      description: "Fixed atomic write race condition on NFS mounts"
    },
    %{
      version: "0.2.0",
      date: "2024-02-01",
      type: :feature,
      description: "Incremental static regeneration with stale-while-revalidate"
    },
    %{
      version: "0.1.1",
      date: "2024-01-15",
      type: :fix,
      description: "Handle LiveView routes with nested layouts correctly"
    },
    %{
      version: "0.1.0",
      date: "2024-01-01",
      type: :feature,
      description: "Initial release - build-time static generation, plug serving, Mix task"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       entries: @entries,
       filter: :all,
       connected: connected?(socket)
     )}
  end

  @impl true
  def handle_event("filter", %{"type" => type}, socket) do
    filter = String.to_existing_atom(type)

    filtered =
      if filter == :all do
        @entries
      else
        Enum.filter(@entries, &(&1.type == filter))
      end

    {:noreply, assign(socket, entries: filtered, filter: filter)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DemoWeb.Layouts.page_header
      title="Changelog"
      subtitle="Release history for PhoenixPrerender"
      mode="liveview"
      mode_description="Prerendered as static HTML, then hydrated via WebSocket. Filter buttons activate after connection."
    />

    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
      <%!-- Connection Status --%>
      <div class="mb-6 flex items-center justify-between">
        <div class="flex items-center space-x-2">
          <button
            phx-click="filter"
            phx-value-type="all"
            class={"px-3 py-1.5 rounded-lg text-sm font-medium transition #{if @filter == :all, do: "bg-blue-100 text-blue-700", else: "bg-gray-100 text-gray-600 hover:bg-gray-200"}"}
          >
            All
          </button>
          <button
            phx-click="filter"
            phx-value-type="feature"
            class={"px-3 py-1.5 rounded-lg text-sm font-medium transition #{if @filter == :feature, do: "bg-blue-100 text-blue-700", else: "bg-gray-100 text-gray-600 hover:bg-gray-200"}"}
          >
            Features
          </button>
          <button
            phx-click="filter"
            phx-value-type="fix"
            class={"px-3 py-1.5 rounded-lg text-sm font-medium transition #{if @filter == :fix, do: "bg-blue-100 text-blue-700", else: "bg-gray-100 text-gray-600 hover:bg-gray-200"}"}
          >
            Fixes
          </button>
        </div>
        <div class="flex items-center space-x-2 text-sm">
          <span class={"w-2 h-2 rounded-full #{if @connected, do: "bg-green-400", else: "bg-gray-300"}"}>
          </span>
          <span class={"#{if @connected, do: "text-green-600", else: "text-gray-400"}"}>
            {if @connected, do: "LiveView connected", else: "Static HTML"}
          </span>
        </div>
      </div>

      <%!-- Entries --%>
      <div class="space-y-4">
        <div
          :for={entry <- @entries}
          id={"entry-#{entry.version}"}
          class="bg-white rounded-xl border border-gray-200 p-6 hover:shadow-sm transition"
        >
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center space-x-3">
              <span class="text-lg font-bold text-gray-900">v{entry.version}</span>
              <span class={"text-xs px-2 py-0.5 rounded-full font-medium #{if entry.type == :feature, do: "bg-blue-100 text-blue-700", else: "bg-orange-100 text-orange-700"}"}>
                {entry.type}
              </span>
            </div>
            <span class="text-sm text-gray-400">{entry.date}</span>
          </div>
          <p class="text-gray-600">{entry.description}</p>
        </div>
      </div>

      <%!-- How it works --%>
      <div class="mt-10 bg-blue-50 rounded-xl border border-blue-200 p-8">
        <h2 class="text-xl font-semibold text-blue-900 mb-4">How LiveView Prerendering Works</h2>
        <div class="space-y-3 text-sm text-blue-800">
          <p>
            <strong>1. Build time:</strong>
            The generator dispatches GET /changelog through the endpoint.
            LiveView renders the static HTML including
            <code class="bg-blue-100 px-1 py-0.5 rounded">data-phx-session</code>
            attributes.
          </p>
          <p>
            <strong>2. First load:</strong>
            The browser receives pre-built HTML instantly. The page is fully
            readable and SEO-friendly before any JavaScript runs.
          </p>
          <p>
            <strong>3. Hydration:</strong>
            Phoenix LiveView JavaScript connects via WebSocket. The filter
            buttons above become interactive. The page is now a full LiveView.
          </p>
        </div>
      </div>
    </div>
    """
  end
end
