defmodule CinemaDaFundacaoWebsitePirata.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      CinemaDaFundacaoWebsitePirataWeb.Telemetry,
      # Start the Ecto repository
      CinemaDaFundacaoWebsitePirata.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: CinemaDaFundacaoWebsitePirata.PubSub},
      # Start Finch
      {Finch, name: CinemaDaFundacaoWebsitePirata.Finch},
      # Start the Endpoint (http/https)
      CinemaDaFundacaoWebsitePirataWeb.Endpoint
      # Start a worker by calling: CinemaDaFundacaoWebsitePirata.Worker.start_link(arg)
      # {CinemaDaFundacaoWebsitePirata.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CinemaDaFundacaoWebsitePirata.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CinemaDaFundacaoWebsitePirataWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
