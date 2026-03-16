defmodule PhoenixPrerenderTest do
  use ExUnit.Case, async: true

  describe "configuration functions" do
    test "output_path/0 returns default" do
      assert PhoenixPrerender.output_path() == "priv/static/prerendered"
    end

    test "url_style/0 returns default" do
      assert PhoenixPrerender.url_style() == :dir_index
    end

    test "enabled?/0 returns default" do
      refute PhoenixPrerender.enabled?()
    end

    test "cache_control/0 returns default" do
      assert PhoenixPrerender.cache_control() == "public, max-age=300"
    end

    test "concurrency/0 returns a positive integer" do
      assert PhoenixPrerender.concurrency() > 0
    end

    test "route_private_key/0 returns default" do
      assert PhoenixPrerender.route_private_key() == :prerender
    end

    test "route_private_value/0 returns default" do
      assert PhoenixPrerender.route_private_value() == true
    end
  end
end
