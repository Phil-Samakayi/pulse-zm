defmodule Pulse.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations) do
      add :name, :string, null: false
      add :city, :string, null: false, default: "Lusaka"
      add :location_type, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:locations, [:name, :city, :location_type])
  end
end
