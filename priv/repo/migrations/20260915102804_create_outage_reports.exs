defmodule Pulse.Repo.Migrations.CreateOutageReports do
  use Ecto.Migration

  def change do
    create table(:outage_reports) do
      add :location_id, references(:locations, on_delete: :delete_all), null: false
      add :utility, :string, null: false
      add :status, :string, null: false
      add :note, :string, size: 280, null: false, default: ""
      add :reported_at, :utc_datetime, null: false
      add :reported_by_id, references(:users, on_delete: :nilify_all)
      add :is_flagged, :boolean, null: false, default: false
      add :flag_reason, :string, size: 280, null: false, default: ""

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:outage_reports, [:location_id, :utility, :reported_at])
    create index(:outage_reports, [:is_flagged])
    create index(:outage_reports, [:reported_by_id])
  end
end
