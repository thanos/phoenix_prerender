defmodule PhoenixPrerender.RendererTest do
  use PhoenixPrerenderWeb.ConnCase, async: true

  alias PhoenixPrerender.Renderer

  describe "render/2" do
    test "renders a valid route" do
      {:ok, html} = Renderer.render(PhoenixPrerenderWeb.Endpoint, "/about")

      assert html =~ "About"
      assert html =~ "<!DOCTYPE html>" or html =~ "<html"
    end

    test "renders nested routes" do
      {:ok, html} = Renderer.render(PhoenixPrerenderWeb.Endpoint, "/docs/terms")

      assert html =~ "Terms"
    end

    test "returns error for non-existent routes" do
      {:error, reason} = Renderer.render(PhoenixPrerenderWeb.Endpoint, "/nonexistent-page-xyz")

      assert {:unexpected_status, _, _} = reason
    end
  end

  describe "render!/2" do
    test "returns HTML directly on success" do
      html = Renderer.render!(PhoenixPrerenderWeb.Endpoint, "/about")
      assert is_binary(html)
      assert html =~ "About"
    end

    test "raises on failure" do
      assert_raise RuntimeError, ~r/Failed to render/, fn ->
        Renderer.render!(PhoenixPrerenderWeb.Endpoint, "/nonexistent-page-xyz")
      end
    end
  end
end
