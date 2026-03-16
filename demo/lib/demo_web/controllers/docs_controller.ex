defmodule DemoWeb.DocsController do
  use DemoWeb, :controller

  def index(conn, _params) do
    render(conn, :index, layout: {DemoWeb.Layouts, :app})
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started, layout: {DemoWeb.Layouts, :app})
  end

  def terms(conn, _params) do
    render(conn, :terms, layout: {DemoWeb.Layouts, :app})
  end
end
