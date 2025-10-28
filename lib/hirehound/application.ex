defmodule Hirehound.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HirehoundWeb.Telemetry,
      Hirehound.Repo,
      {DNSCluster, query: Application.get_env(:hirehound, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:hirehound, Oban)},
      {Phoenix.PubSub, name: Hirehound.PubSub},
      # Start a worker by calling: Hirehound.Worker.start_link(arg)
      # {Hirehound.Worker, arg},
      # Start to serve requests, typically the last entry
      HirehoundWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hirehound.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HirehoundWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
