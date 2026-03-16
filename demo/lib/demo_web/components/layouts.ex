defmodule DemoWeb.Layouts do
  @moduledoc false
  use DemoWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>PhoenixPrerender Demo</title>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <nav style="padding: 1rem; background: #f0f0f0; margin-bottom: 1rem;">
      <a href="/">Home</a> |
      <a href="/about">About</a> |
      <a href="/features">Features</a> |
      <a href="/docs">Docs</a> |
      <a href="/docs/getting-started">Getting Started</a> |
      <a href="/docs/terms">Terms</a> |
      <a href="/changelog">Changelog</a> |
      <a href="/contact">Contact (dynamic)</a>
    </nav>
    <main style="padding: 1rem;">
      {@inner_content}
    </main>
    """
  end
end
