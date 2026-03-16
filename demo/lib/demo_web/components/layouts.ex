defmodule DemoWeb.Layouts do
  @moduledoc false
  use DemoWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>PhoenixPrerender Demo</title>
        <script src="https://cdn.tailwindcss.com">
        </script>
        <script>
          tailwind.config = {
            theme: {
              extend: {
                colors: {
                  brand: { 50: '#faf5ff', 100: '#f3e8ff', 200: '#e9d5ff', 300: '#d8b4fe', 400: '#c084fc', 500: '#a855f7', 600: '#9333ea', 700: '#7e22ce', 800: '#6b21a8', 900: '#581c87' }
                }
              }
            }
          }
        </script>
        <style>
          .gradient-bg { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
          .gradient-text { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
          .code-block { background: #1e1e2e; color: #cdd6f4; border-radius: 0.75rem; padding: 1.5rem; font-family: 'Menlo', 'Monaco', 'Courier New', monospace; font-size: 0.875rem; line-height: 1.7; overflow-x: auto; margin: 0; }
        </style>
        <script defer src="/assets/phoenix.min.js">
        </script>
        <script defer src="/assets/phoenix_live_view.min.js">
        </script>
        <script defer src="/assets/app.js">
        </script>
      </head>
      <body class="h-full bg-gray-50 antialiased">
        {@inner_content}
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <div class="min-h-full">
      <nav class="bg-white border-b border-gray-200 sticky top-0 z-50">
        <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-14">
            <div class="flex items-center space-x-1">
              <a
                href="/"
                class="flex items-center space-x-2 px-2 py-1 rounded-lg hover:bg-gray-50 transition"
              >
                <span class="text-lg font-bold gradient-text">PhoenixPrerender</span>
              </a>
              <span class="text-gray-300 mx-1">|</span>
              <div class="hidden sm:flex items-center space-x-0.5">
                <.nav_link href="/about" label="About" badge="prerendered" />
                <.nav_link href="/features" label="Features" badge="prerendered" />
                <.nav_link href="/docs" label="Docs" badge="prerendered" />
                <.nav_link href="/changelog" label="Changelog" badge="liveview" />
                <.nav_link href="/status" label="Status" badge="isr" />
                <.nav_link href="/contact" label="Contact" badge="dynamic" />
                <.nav_link href="/dashboard" label="Dashboard" badge="dynamic" />
              </div>
            </div>
          </div>
        </div>
      </nav>

      <main>
        {@inner_content}
      </main>

      <footer class="bg-white border-t border-gray-200 mt-16">
        <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="flex flex-col md:flex-row justify-between items-center space-y-4 md:space-y-0">
            <p class="text-sm text-gray-500">
              PhoenixPrerender Demo &mdash; static prerendering for Phoenix
            </p>
            <div class="flex items-center space-x-4 text-sm text-gray-400">
              <span class="flex items-center space-x-1">
                <span class="w-2 h-2 rounded-full bg-purple-400"></span>
                <span>Prerendered</span>
              </span>
              <span class="flex items-center space-x-1">
                <span class="w-2 h-2 rounded-full bg-blue-400"></span>
                <span>LiveView</span>
              </span>
              <span class="flex items-center space-x-1">
                <span class="w-2 h-2 rounded-full bg-amber-400"></span>
                <span>ISR</span>
              </span>
              <span class="flex items-center space-x-1">
                <span class="w-2 h-2 rounded-full bg-green-400"></span>
                <span>Dynamic</span>
              </span>
            </div>
          </div>
        </div>
      </footer>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :badge, :string, default: nil

  defp nav_link(assigns) do
    badge_color =
      case assigns.badge do
        "prerendered" -> "bg-purple-100 text-purple-700"
        "liveview" -> "bg-blue-100 text-blue-700"
        "isr" -> "bg-amber-100 text-amber-700"
        "dynamic" -> "bg-green-100 text-green-700"
        _ -> ""
      end

    assigns = assign(assigns, :badge_color, badge_color)

    ~H"""
    <a
      href={@href}
      class="flex items-center space-x-1 px-2.5 py-1.5 rounded-lg text-sm text-gray-600 hover:text-gray-900 hover:bg-gray-50 transition"
    >
      <span>{@label}</span>
      <span :if={@badge} class={"text-[10px] px-1.5 py-0.5 rounded-full font-medium #{@badge_color}"}>
        {@badge}
      </span>
    </a>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :mode, :string, required: true
  attr :mode_description, :string, default: nil

  def page_header(assigns) do
    {badge_color, badge_bg} =
      case assigns.mode do
        "prerendered" -> {"text-purple-700", "bg-purple-50 border-purple-200"}
        "liveview" -> {"text-blue-700", "bg-blue-50 border-blue-200"}
        "isr" -> {"text-amber-700", "bg-amber-50 border-amber-200"}
        "dynamic" -> {"text-green-700", "bg-green-50 border-green-200"}
        _ -> {"text-gray-700", "bg-gray-50 border-gray-200"}
      end

    dot_color =
      case assigns.mode do
        "prerendered" -> "bg-purple-400"
        "liveview" -> "bg-blue-400"
        "isr" -> "bg-amber-400"
        "dynamic" -> "bg-green-400"
        _ -> "bg-gray-400"
      end

    assigns =
      assigns
      |> assign(:badge_color, badge_color)
      |> assign(:badge_bg, badge_bg)
      |> assign(:dot_color, dot_color)

    ~H"""
    <div class="bg-white border-b border-gray-200">
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="flex items-start justify-between">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">{@title}</h1>
            <p :if={@subtitle} class="mt-2 text-lg text-gray-500">{@subtitle}</p>
          </div>
          <div class={"flex items-center space-x-2 px-3 py-1.5 rounded-lg border #{@badge_bg}"}>
            <span class={"w-2 h-2 rounded-full #{@dot_color}"}></span>
            <span class={"text-sm font-medium #{@badge_color}"}>{@mode}</span>
          </div>
        </div>
        <p :if={@mode_description} class="mt-3 text-sm text-gray-400">{@mode_description}</p>
      </div>
    </div>
    """
  end
end
