defmodule PhoenixPrerender.RouteTest do
  use ExUnit.Case, async: true

  alias PhoenixPrerender.Route

  describe "discover/1" do
    test "discovers routes marked with prerender: true" do
      routes = Route.discover(PhoenixPrerenderWeb.Router)
      paths = Enum.map(routes, & &1.path)

      assert "/about" in paths
      assert "/docs" in paths
      assert "/docs/terms" in paths
    end

    test "discovers routes with prerender: :bots_only and :always" do
      routes = Route.discover(PhoenixPrerenderWeb.Router)
      paths = Enum.map(routes, & &1.path)

      assert "/changelog" in paths
      assert "/status" in paths
    end

    test "returns prerender_mode for each route" do
      routes = Route.discover(PhoenixPrerenderWeb.Router)

      about = Enum.find(routes, &(&1.path == "/about"))
      assert about.prerender_mode == true

      changelog = Enum.find(routes, &(&1.path == "/changelog"))
      assert changelog.prerender_mode == :bots_only

      status = Enum.find(routes, &(&1.path == "/status"))
      assert status.prerender_mode == :always
    end

    test "returns isr flag for each route" do
      routes = Route.discover(PhoenixPrerenderWeb.Router)

      about = Enum.find(routes, &(&1.path == "/about"))
      assert about.isr == false

      changelog = Enum.find(routes, &(&1.path == "/changelog"))
      assert changelog.isr == false

      status = Enum.find(routes, &(&1.path == "/status"))
      assert status.isr == true
    end

    test "excludes routes without prerender metadata" do
      routes = Route.discover(PhoenixPrerenderWeb.Router)
      paths = Enum.map(routes, & &1.path)

      refute "/" in paths
    end

    test "returns route metadata" do
      routes = Route.discover(PhoenixPrerenderWeb.Router)
      about = Enum.find(routes, &(&1.path == "/about"))

      assert about.verb == :get
      assert about.plug == PhoenixPrerenderWeb.PageController
      assert about.plug_opts == :about
    end
  end

  describe "discover/2 with custom key/value" do
    test "filters by custom private key" do
      routes =
        Route.discover(PhoenixPrerenderWeb.Router,
          private_key: :nonexistent_key,
          private_value: true
        )

      assert routes == []
    end
  end

  describe "paths/1" do
    test "returns only path strings" do
      paths = Route.paths(PhoenixPrerenderWeb.Router)

      assert is_list(paths)
      assert Enum.all?(paths, &is_binary/1)
      assert "/about" in paths
    end
  end
end
