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

  # Prerendered routes using the macro
  scope "/", DemoWeb do
    pipe_through :browser

    get "/", PageController, :home

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

  # LiveView prerendered routes
  scope "/", DemoWeb do
    pipe_through :browser

    live "/changelog", ChangelogLive, :index, metadata: %{prerender: true}
  end

  # Dynamic routes (not prerendered)
  scope "/", DemoWeb do
    pipe_through :browser

    get "/contact", PageController, :contact
  end
end
