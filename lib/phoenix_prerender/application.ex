defmodule PhoenixPrerender.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixPrerenderWeb.Telemetry,
      PhoenixPrerender.Repo,
      {DNSCluster, query: Application.get_env(:phoenix_prerender, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PhoenixPrerender.PubSub},
      # Start a worker by calling: PhoenixPrerender.Worker.start_link(arg)
      # {PhoenixPrerender.Worker, arg},
      # Start to serve requests, typically the last entry
      PhoenixPrerenderWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PhoenixPrerender.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhoenixPrerenderWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
