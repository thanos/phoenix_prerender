defmodule DemoWeb.Router do
  use DemoWeb, :router

  import PhoenixPrerender

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Landing page (dynamic - always fresh)
  scope "/", DemoWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Prerendered controller routes
  scope "/", DemoWeb do
    pipe_through :browser

    prerender do
      get "/about", PageController, :about
      get "/features", PageController, :features
    end
  end

  # Scoped prerendered routes
  scope "/docs", DemoWeb do
    pipe_through :browser

    prerender do
      get "/", DocsController, :index
      get "/getting-started", DocsController, :getting_started
      get "/terms", DocsController, :terms
    end
  end

  # Prerendered LiveView routes
  scope "/", DemoWeb do
    pipe_through :browser

    # LiveView + prerender: static HTML first, then hydrated
    live "/changelog", ChangelogLive, :index, metadata: %{prerender: true}

    # ISR candidate: prerendered, regenerated when stale
    live "/status", StatusLive, :index, metadata: %{prerender: true}
  end

  # Dynamic routes (NOT prerendered)
  scope "/", DemoWeb do
    pipe_through :browser

    get "/contact", PageController, :contact
    get "/dashboard", PageController, :dashboard
  end
end
