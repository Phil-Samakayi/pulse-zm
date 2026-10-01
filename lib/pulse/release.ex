defmodule Pulse.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed (e.g. inside the Docker image, which has no `mix` binary).

  Run from inside the running container with:

      docker compose run --rm app bin/pulse eval "Pulse.Release.migrate"
  """
  @app :pulse

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
