defmodule PhoenixPrerenderWeb.PageController do
  use PhoenixPrerenderWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def docs(conn, _params) do
    render(conn, :docs)
  end

  def terms(conn, _params) do
    render(conn, :terms)
  end
end
