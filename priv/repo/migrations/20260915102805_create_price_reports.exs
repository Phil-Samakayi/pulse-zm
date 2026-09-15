defmodule Pulse.Repo.Migrations.CreatePriceReports do
  use Ecto.Migration

  def change do
    create table(:price_reports) do
      add :location_id, references(:locations, on_delete: :delete_all), null: false
      add :commodity, :string, null: false
      add :commodity_other, :string, size: 80, null: false, default: ""
      add :unit, :string, null: false
      add :price_kwacha, :decimal, null: false
      add :note, :string, size: 280, null: false, default: ""
      add :reported_at, :utc_datetime, null: false
      add :reported_by_id, references(:users, on_delete: :nilify_all)
      add :is_flagged, :boolean, null: false, default: false
      add :flag_reason, :string, size: 280, null: false, default: ""

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:price_reports, [:location_id, :commodity, :reported_at])
    create index(:price_reports, [:is_flagged])
    create index(:price_reports, [:reported_by_id])
  end
end
