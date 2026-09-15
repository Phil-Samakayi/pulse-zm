defmodule Pulse.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string, null: false
      add :hashed_password, :string, null: false
      # Gates the moderation LiveView (see Pulse.Reports) — the simplest
      # thing that could work rather than a full roles system.
      add :is_admin, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])
  end
end
