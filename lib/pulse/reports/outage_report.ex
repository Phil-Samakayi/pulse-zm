defmodule Pulse.Reports.OutageReport do
  use Ecto.Schema
  import Ecto.Changeset

  @electricity "electricity"
  @water "water"
  @up "up"
  @down "down"

  def electricity, do: @electricity
  def water, do: @water
  def utilities, do: [@electricity, @water]
  def up, do: @up
  def down, do: @down
  def statuses, do: [@up, @down]

  schema "outage_reports" do
    belongs_to :location, Pulse.Reports.Location
    field :utility, :string
    field :status, :string
    field :note, :string, default: ""
    field :reported_at, :utc_datetime
    belongs_to :reported_by, Pulse.Accounts.User
    field :is_flagged, :boolean, default: false
    field :flag_reason, :string, default: ""

    # Honeypot — see Pulse.Reports.Location for why this exists and why
    # it's `virtual: true`. Bound in LocationLive.Show's outage form.
    field :website, :string, virtual: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Changeset for a real, user-submitted report. `reported_at` is always set
  to now here — it is never accepted from the caller's attrs, the same way
  the Django version marked it read-only on the serializer. Seeding
  backdated example data goes through `Pulse.Repo.insert!/1` directly with
  a struct instead, bypassing this changeset entirely.
  """
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:location_id, :utility, :status, :note, :reported_by_id, :website])
    |> validate_required([:location_id, :utility, :status])
    |> validate_inclusion(:utility, utilities())
    |> validate_inclusion(:status, statuses())
    |> validate_length(:note, max: 280)
    |> put_change(:reported_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:location_id)
  end

  def flag_changeset(report, attrs) do
    report
    |> cast(attrs, [:is_flagged, :flag_reason])
    |> validate_length(:flag_reason, max: 280)
  end
end
