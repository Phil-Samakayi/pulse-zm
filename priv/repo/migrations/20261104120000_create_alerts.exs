defmodule Pulse.Repo.Migrations.CreateAlerts do
  use Ecto.Migration

  def change do
    # One row per browser that has allowed notifications (a user can have
    # several: phone, laptop). The endpoint is unique to that browser.
    create table(:push_subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:push_subscriptions, [:endpoint])
    create index(:push_subscriptions, [:user_id])

    # What a user wants to hear about. A location alert has location_id
    # set ("tell me when power/water changes here"); a price alert has
    # commodity and max_price_kwacha set ("tell me when it's at or below
    # this anywhere"). last_sent_at lets price alerts avoid repeating
    # themselves.
    create table(:alerts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :location_id, references(:locations, on_delete: :delete_all)
      add :commodity, :string
      add :max_price_kwacha, :decimal
      add :last_sent_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:alerts, [:user_id, :location_id],
             where: "location_id IS NOT NULL",
             name: :alerts_user_location_index
           )

    create unique_index(:alerts, [:user_id, :commodity],
             where: "commodity IS NOT NULL",
             name: :alerts_user_commodity_index
           )

    create index(:alerts, [:location_id])
    create index(:alerts, [:commodity])
  end
end
