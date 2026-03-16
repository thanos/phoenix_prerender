defmodule DemoWeb.PageController do
  use DemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: {DemoWeb.Layouts, :app})
  end

  def about(conn, _params) do
    render(conn, :about, layout: {DemoWeb.Layouts, :app})
  end

  def features(conn, _params) do
    render(conn, :features, layout: {DemoWeb.Layouts, :app})
  end

  def contact(conn, _params) do
    render(conn, :contact, layout: {DemoWeb.Layouts, :app})
  end
end
