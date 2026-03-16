defmodule PhoenixPrerenderWeb.Router do
  use PhoenixPrerenderWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhoenixPrerenderWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PhoenixPrerenderWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/about", PageController, :about, metadata: %{prerender: true}
    get "/docs", PageController, :docs, metadata: %{prerender: true}

    scope "/docs" do
      get "/terms", PageController, :terms, metadata: %{prerender: true}
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", PhoenixPrerenderWeb do
  #   pipe_through :api
  # end
end
