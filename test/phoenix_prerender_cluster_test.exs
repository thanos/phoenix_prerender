defmodule PhoenixPrerender.ClusterTest do
  use ExUnit.Case, async: false

  alias PhoenixPrerender.Cluster

  doctest PhoenixPrerender.Cluster

  describe "topic/0" do
    test "returns the PubSub topic" do
      assert Cluster.topic() == "phoenix_prerender"
    end
  end

  describe "subscribe/0" do
    test "returns error when no pubsub configured" do
      assert {:error, :no_pubsub} = Cluster.subscribe()
    end

    test "subscribes successfully when pubsub is configured" do
      Application.put_env(:phoenix_prerender, :pubsub, PhoenixPrerender.PubSub)
      assert :ok = Cluster.subscribe()
    after
      Application.delete_env(:phoenix_prerender, :pubsub)
    end
  end

  describe "broadcast_regenerated/1" do
    test "returns :ok when no pubsub configured" do
      assert :ok = Cluster.broadcast_regenerated("/about")
    end

    test "broadcasts when pubsub is configured" do
      Application.put_env(:phoenix_prerender, :pubsub, PhoenixPrerender.PubSub)

      # Subscribe first so we can verify the broadcast
      :ok = Cluster.subscribe()

      assert :ok = Cluster.broadcast_regenerated("/about")

      # Verify we receive the broadcast message
      assert_receive {:regenerated, "/about"}
    after
      Application.delete_env(:phoenix_prerender, :pubsub)
    end
  end

  describe "handle_regenerated/1" do
    test "does not raise when page cache is not started" do
      assert :ok = Cluster.handle_regenerated("/some/path")
    end

    test "deletes from page cache when running" do
      # Start the page cache
      start_supervised!(PhoenixPrerender.PageCache)

      # Put something in the cache
      PhoenixPrerender.PageCache.put("/cached-page", "<html>cached</html>")
      assert {:ok, _, _} = PhoenixPrerender.PageCache.get("/cached-page")

      # Handle regenerated should delete the cache entry
      assert :ok = Cluster.handle_regenerated("/cached-page")

      # Cache entry should be gone
      assert :miss = PhoenixPrerender.PageCache.get("/cached-page")
    end
  end

  describe "regenerate/4" do
    setup do
      output_path = "test/tmp/cluster_test"
      File.rm_rf!(output_path)
      File.mkdir_p!(output_path)
      start_supervised!({PhoenixPrerender.Regenerator, endpoint: PhoenixPrerenderWeb.Endpoint})
      on_exit(fn -> File.rm_rf!(output_path) end)
      %{output_path: output_path}
    end

    test "regenerates a page with cluster-wide locking", %{output_path: output_path} do
      assert :ok =
               Cluster.regenerate(
                 "/about",
                 PhoenixPrerenderWeb.Endpoint,
                 output_path,
                 :dir_index
               )

      file_path = Path.join(output_path, "about/index.html")
      assert File.exists?(file_path)
      assert File.read!(file_path) =~ "About"
    end

    test "returns error for invalid path", %{output_path: output_path} do
      assert {:error, _} =
               Cluster.regenerate(
                 "/nonexistent-page-xyz",
                 PhoenixPrerenderWeb.Endpoint,
                 output_path,
                 :dir_index
               )
    end

    test "broadcasts after successful regeneration", %{output_path: output_path} do
      Application.put_env(:phoenix_prerender, :pubsub, PhoenixPrerender.PubSub)
      :ok = Cluster.subscribe()

      assert :ok =
               Cluster.regenerate(
                 "/about",
                 PhoenixPrerenderWeb.Endpoint,
                 output_path,
                 :dir_index
               )

      assert_receive {:regenerated, "/about"}
    after
      Application.delete_env(:phoenix_prerender, :pubsub)
    end
  end
end
