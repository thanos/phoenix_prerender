defmodule DemoWeb.StatusLive do
  @moduledoc """
  A LiveView demonstrating incremental static regeneration (ISR).

  This page is prerendered at build time and marked for ISR. When the
  prerendered file becomes stale, the next request triggers a background
  regeneration. The stale content is served immediately while the page
  refreshes behind the scenes.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(1000, self(), :tick)
    end

    {:ok,
     assign(socket,
       generated_at: DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC"),
       current_time: DateTime.utc_now() |> Calendar.strftime("%H:%M:%S UTC"),
       connected: connected?(socket),
       tick_count: 0
     )}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply,
     assign(socket,
       current_time: DateTime.utc_now() |> Calendar.strftime("%H:%M:%S UTC"),
       tick_count: socket.assigns.tick_count + 1
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DemoWeb.Layouts.page_header
      title="System Status"
      subtitle="Demonstrating incremental static regeneration"
      mode="isr"
      mode_description="This page is prerendered and regenerated in the background when stale. The generated_at timestamp freezes at build time."
    />

    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
      <%!-- Status Cards --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        <div class="bg-white rounded-xl border border-gray-200 p-6">
          <p class="text-sm text-gray-500 mb-1">Page Generated At</p>
          <p class="text-xl font-mono font-bold text-amber-700">{@generated_at}</p>
          <p class="text-xs text-gray-400 mt-2">
            This timestamp was frozen when the page was rendered.
            With ISR, it updates when the page is regenerated in the background.
          </p>
        </div>
        <div class="bg-white rounded-xl border border-gray-200 p-6">
          <p class="text-sm text-gray-500 mb-1">Live Clock</p>
          <p class="text-xl font-mono font-bold text-blue-700">{@current_time}</p>
          <p class="text-xs text-gray-400 mt-2">
            {if @connected,
              do: "Updating live via WebSocket (#{@tick_count} ticks)",
              else: "Will update after LiveView connects"}
          </p>
        </div>
      </div>

      <%!-- ISR Explanation --%>
      <div class="bg-white rounded-xl border border-gray-200 p-8 mb-6">
        <h2 class="text-xl font-semibold text-gray-900 mb-4">How ISR Works on This Page</h2>
        <div class="space-y-4">
          <div class="flex items-start space-x-4">
            <span class="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center text-sm font-bold">
              1
            </span>
            <div>
              <p class="font-medium text-gray-900">Build time generation</p>
              <p class="text-sm text-gray-500">
                <code class="bg-gray-100 px-1 py-0.5 rounded text-xs">mix phoenix.prerender</code>
                renders this page
                and writes it to disk. The "Page Generated At" timestamp is frozen.
              </p>
            </div>
          </div>
          <div class="flex items-start space-x-4">
            <span class="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center text-sm font-bold">
              2
            </span>
            <div>
              <p class="font-medium text-gray-900">First request</p>
              <p class="text-sm text-gray-500">
                The plug serves the static file instantly. If the file is older than
                <code class="bg-gray-100 px-1 py-0.5 rounded text-xs">revalidate</code>
                seconds, a background regeneration is triggered.
              </p>
            </div>
          </div>
          <div class="flex items-start space-x-4">
            <span class="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center text-sm font-bold">
              3
            </span>
            <div>
              <p class="font-medium text-gray-900">Background regeneration</p>
              <p class="text-sm text-gray-500">
                The Regenerator re-renders the page through the endpoint, writes fresh HTML
                atomically, and updates the ETS page cache. An ETS lock prevents duplicate work.
              </p>
            </div>
          </div>
          <div class="flex items-start space-x-4">
            <span class="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center text-sm font-bold">
              4
            </span>
            <div>
              <p class="font-medium text-gray-900">Next request</p>
              <p class="text-sm text-gray-500">
                The fresh page is served. The "Page Generated At" timestamp is now updated.
                The user who triggered regeneration saw the stale page but got an instant response.
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Comparison --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <div class="bg-amber-50 rounded-xl border border-amber-200 p-6">
          <h3 class="font-semibold text-amber-900 mb-2">ISR (this page)</h3>
          <ul class="space-y-1 text-sm text-amber-800">
            <li>&#10003; Instant response (serves stale)</li>
            <li>&#10003; Background regeneration</li>
            <li>&#10003; No full rebuild needed</li>
            <li>&#10003; Thundering herd prevention</li>
          </ul>
        </div>
        <div class="bg-green-50 rounded-xl border border-green-200 p-6">
          <h3 class="font-semibold text-green-900 mb-2">
            Dynamic (<a href="/dashboard" class="underline">/dashboard</a>)
          </h3>
          <ul class="space-y-1 text-sm text-green-800">
            <li>&#10003; Always fresh data</li>
            <li>&#10003; User-specific content</li>
            <li>&#10007; Full render on every request</li>
            <li>&#10007; Higher server load</li>
          </ul>
        </div>
      </div>

      <%!-- Config --%>
      <div class="bg-white rounded-xl border border-gray-200 p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-3">ISR Configuration</h3>
        <pre class="code-block text-sm"><code>
        config :phoenix_prerender,
          enabled: true,
          isr: true,
          revalidate: 300  # seconds
        </code></pre>
      </div>
    </div>
    """
  end
end
