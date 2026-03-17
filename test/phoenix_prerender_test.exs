defmodule PhoenixPrerenderTest do
  use ExUnit.Case, async: false

  doctest PhoenixPrerender

  describe "configuration functions" do
    test "output_path/0 returns default" do
      assert PhoenixPrerender.output_path() == "priv/static/prerendered"
    end

    test "output_path/0 returns custom value" do
      Application.put_env(:phoenix_prerender, :output_path, "_build/custom")
      assert PhoenixPrerender.output_path() == "_build/custom"
    after
      Application.delete_env(:phoenix_prerender, :output_path)
    end

    test "url_style/0 returns default" do
      assert PhoenixPrerender.url_style() == :dir_index
    end

    test "url_style/0 returns custom value" do
      Application.put_env(:phoenix_prerender, :url_style, :file)
      assert PhoenixPrerender.url_style() == :file
    after
      Application.delete_env(:phoenix_prerender, :url_style)
    end

    test "enabled?/0 returns default" do
      refute PhoenixPrerender.enabled?()
    end

    test "enabled?/0 returns custom value" do
      Application.put_env(:phoenix_prerender, :enabled, true)
      assert PhoenixPrerender.enabled?()
    after
      Application.delete_env(:phoenix_prerender, :enabled)
    end

    test "cache_control/0 returns default" do
      assert PhoenixPrerender.cache_control() == "public, max-age=300"
    end

    test "cache_control/0 returns custom value" do
      Application.put_env(:phoenix_prerender, :cache_control, "no-cache")
      assert PhoenixPrerender.cache_control() == "no-cache"
    after
      Application.delete_env(:phoenix_prerender, :cache_control)
    end

    test "concurrency/0 returns a positive integer" do
      assert PhoenixPrerender.concurrency() > 0
    end

    test "concurrency/0 returns custom value" do
      Application.put_env(:phoenix_prerender, :concurrency, 4)
      assert PhoenixPrerender.concurrency() == 4
    after
      Application.delete_env(:phoenix_prerender, :concurrency)
    end

    test "route_private_key/0 returns default" do
      assert PhoenixPrerender.route_private_key() == :prerender
    end

    test "route_private_value/0 returns default" do
      assert PhoenixPrerender.route_private_value() == true
    end

    test "strict_paths/0 returns default" do
      assert PhoenixPrerender.strict_paths() == true
    end

    test "strict_paths/0 returns custom value" do
      Application.put_env(:phoenix_prerender, :strict_paths, false)
      refute PhoenixPrerender.strict_paths()
    after
      Application.delete_env(:phoenix_prerender, :strict_paths)
    end
  end

  describe "prerender/1 macro" do
    test "routes defined with prerender metadata are discovered" do
      # The test router defines routes with metadata: %{prerender: true}
      # Verify that route discovery works, proving the metadata pattern works
      routes = PhoenixPrerender.Route.discover(PhoenixPrerenderWeb.Router)
      paths = Enum.map(routes, & &1.path)

      assert "/about" in paths
      assert "/docs" in paths
      assert "/docs/terms" in paths
      # "/" is NOT prerendered in the test router
      refute "/" in paths
    end
  end
end
