defmodule PhoenixPrerender.StaticAssetTest do
  use ExUnit.Case, async: true

  alias PhoenixPrerender.StaticAsset

  doctest PhoenixPrerender.StaticAsset

  describe "static_path/2" do
    test "returns the path via the endpoint when available" do
      # The test endpoint is started, so static_path works
      result = StaticAsset.static_path(PhoenixPrerenderWeb.Endpoint, "/assets/app.css")
      assert is_binary(result)
      assert result =~ "/assets/app"
    end

    test "returns the original path when endpoint function is undefined" do
      defmodule __MODULE__.NoStaticEndpoint do
        # No static_path/1 defined
      end

      assert StaticAsset.static_path(__MODULE__.NoStaticEndpoint, "/assets/app.css") ==
               "/assets/app.css"
    end

    test "returns the original path when endpoint raises ArgumentError" do
      defmodule __MODULE__.BadEndpoint do
        def static_path(_path), do: raise(ArgumentError, "no manifest")
      end

      assert StaticAsset.static_path(__MODULE__.BadEndpoint, "/assets/app.css") ==
               "/assets/app.css"
    end
  end

  describe "delegate in PhoenixPrerender" do
    test "static_asset_path/2 delegates to StaticAsset.static_path/2" do
      result = PhoenixPrerender.static_asset_path(PhoenixPrerenderWeb.Endpoint, "/assets/app.css")
      assert is_binary(result)
    end
  end
end
