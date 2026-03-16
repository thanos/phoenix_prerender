defmodule PhoenixPrerender.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixPrerenderWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:phoenix_prerender, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PhoenixPrerender.PubSub},
      PhoenixPrerenderWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PhoenixPrerender.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PhoenixPrerenderWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
