defmodule Pulse.Repo.Migrations.AddModerationToLocations do
  use Ecto.Migration

  def change do
    alter table(:locations) do
      add :status, :string, null: false, default: "approved"
      add :submitted_by_id, references(:users, on_delete: :nilify_all)
      add :rejection_note, :string, size: 280, null: false, default: ""
    end

    create index(:locations, [:status])
    create index(:locations, [:submitted_by_id])
  end
end
