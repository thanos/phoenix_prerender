defmodule PhoenixPrerender.ClusterTest do
  use ExUnit.Case, async: true

  alias PhoenixPrerender.Cluster

  describe "topic/0" do
    test "returns the PubSub topic" do
      assert is_binary(Cluster.topic())
    end
  end

  describe "subscribe/0" do
    test "returns error when no pubsub configured" do
      assert {:error, :no_pubsub} = Cluster.subscribe()
    end
  end

  describe "handle_regenerated/1" do
    test "does not raise when page cache is not started" do
      assert :ok = Cluster.handle_regenerated("/some/path")
    end
  end
end
