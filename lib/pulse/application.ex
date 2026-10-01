defmodule Pulse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PulseWeb.Telemetry,
      Pulse.Repo,
      {Ecto.Migrator,
        repos: Application.fetch_env!(:pulse, :ecto_repos),
        skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:pulse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pulse.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Pulse.Finch},
      # Start a worker by calling: Pulse.Worker.start_link(arg)
      # {Pulse.Worker, arg},
      # Start to serve requests, typically the last entry
      PulseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pulse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PulseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Migrations are skipped by default in a release. On platforms where you
  # can run a one-off command against the release (e.g. SSH'd into the
  # Oracle VM: `docker compose run --rm app bin/pulse eval
  # "Pulse.Release.migrate"`), leave RUN_MIGRATIONS_ON_BOOT unset and keep
  # doing that.
  #
  # On platforms with no shell/one-off-command access on the free tier
  # (e.g. Render's free web services), set RUN_MIGRATIONS_ON_BOOT=true so
  # the Ecto.Migrator child above runs migrations itself on every boot.
  # This is safe to leave on permanently: Ecto tracks which migrations
  # already ran and skips them, so re-running on every restart is a no-op
  # once the schema is up to date.
  defp skip_migrations?() do
    System.get_env("RUN_MIGRATIONS_ON_BOOT") != "true"
  end
end
