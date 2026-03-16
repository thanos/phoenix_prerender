defmodule PhoenixPrerenderWeb.PageHTML do
  @moduledoc false
  use PhoenixPrerenderWeb, :html

  def home(assigns) do
    ~H"""
    <h1>Welcome</h1>
    """
  end

  def about(assigns) do
    ~H"""
    <h1>About</h1>
    <p>This is the about page.</p>
    """
  end

  def docs(assigns) do
    ~H"""
    <h1>Docs</h1>
    <p>Documentation index.</p>
    """
  end

  def terms(assigns) do
    ~H"""
    <h1>Terms</h1>
    <p>Terms of service.</p>
    """
  end
end
