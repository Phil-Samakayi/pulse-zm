defmodule Pulse.Alerts.PushSubscription do
  @moduledoc """
  One browser that has allowed Pulse to send it notifications. `endpoint`
  is the push service URL for that browser; `p256dh` and `auth` are the
  keys its messages are encrypted with. See `Pulse.Push`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "push_subscriptions" do
    belongs_to :user, Pulse.Accounts.User
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:user_id, :endpoint, :p256dh, :auth])
    |> validate_required([:user_id, :endpoint, :p256dh, :auth])
    |> validate_format(:endpoint, ~r{\Ahttps://}, message: "must be an https URL")
    |> unique_constraint(:endpoint)
  end

  @doc "The subscription in the JSON shape the browser produced, which `Pulse.Push` sends to."
  def to_json(%__MODULE__{} = subscription) do
    Jason.encode!(%{
      endpoint: subscription.endpoint,
      keys: %{p256dh: subscription.p256dh, auth: subscription.auth}
    })
  end
end
