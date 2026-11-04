defmodule Pulse.Alerts.Alert do
  @moduledoc """
  Something a user wants to be told about. A *location alert* has
  `location_id` set: tell me when power or water changes there. A *price
  alert* has `commodity` and `max_price_kwacha` set: tell me when it's
  reported at or below that price anywhere. See `Pulse.Alerts`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "alerts" do
    belongs_to :user, Pulse.Accounts.User
    belongs_to :location, Pulse.Reports.Location
    field :commodity, :string
    field :max_price_kwacha, :decimal
    field :last_sent_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def location_changeset(alert, attrs) do
    alert
    |> cast(attrs, [:user_id, :location_id])
    |> validate_required([:user_id, :location_id])
    |> unique_constraint([:user_id, :location_id], name: :alerts_user_location_index)
  end
end
