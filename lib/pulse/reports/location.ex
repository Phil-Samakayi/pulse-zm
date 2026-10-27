defmodule Pulse.Reports.Location do
  use Ecto.Schema
  import Ecto.Changeset

  @residential "residential"
  @market "market"

  @pending "pending"
  @approved "approved"
  @rejected "rejected"

  def residential, do: @residential
  def market, do: @market
  def location_types, do: [@residential, @market]

  def pending, do: @pending
  def approved, do: @approved
  def rejected, do: @rejected
  def statuses, do: [@pending, @approved, @rejected]

  schema "locations" do
    field :name, :string
    field :city, :string, default: "Lusaka"
    field :location_type, :string
    field :status, :string, default: @approved
    field :rejection_note, :string, default: ""
    belongs_to :submitted_by, Pulse.Accounts.User

    # Honeypot for the public submission form — invisible to real users,
    # but a spam bot's form-filler will often populate every input it
    # finds. Never cast on the admin/seed changeset, only on
    # `submission_changeset/2`, and `virtual: true` means it's never
    # written to the database even if something upstream forgets to
    # strip it.
    field :website, :string, virtual: true

    has_many :outage_reports, Pulse.Reports.OutageReport
    has_many :price_reports, Pulse.Reports.PriceReport

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Admin/seed path: full control over every field, including status."
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :city, :location_type, :status, :rejection_note])
    |> validate_required([:name, :city, :location_type])
    |> validate_inclusion(:location_type, location_types())
    |> validate_inclusion(:status, statuses())
    |> validate_length(:rejection_note, max: 280)
    |> unique_constraint([:name, :city, :location_type])
  end

  @doc """
  A regular user proposing a new location. Always lands as "pending" —
  status is never accepted from the caller's attrs here, the same way
  `reported_at` is forced server-side on outage/price reports, so there's
  no way to submit a pre-approved location through this path.
  """
  def submission_changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :city, :location_type, :submitted_by_id, :website])
    |> validate_required([:name, :city, :location_type, :submitted_by_id])
    |> validate_inclusion(:location_type, location_types())
    |> put_change(:status, @pending)
    |> unique_constraint([:name, :city, :location_type])
    |> foreign_key_constraint(:submitted_by_id)
  end

  @doc "Admin reviewing a pending location: approve, or reject with a note."
  def review_changeset(location, attrs) do
    location
    |> cast(attrs, [:status, :rejection_note])
    |> validate_required([:status])
    |> validate_inclusion(:status, [@approved, @rejected])
    |> validate_length(:rejection_note, max: 280)
    |> validate_rejection_note()
  end

  defp validate_rejection_note(changeset) do
    if get_field(changeset, :status) == @rejected and
         (get_field(changeset, :rejection_note) || "") == "" do
      add_error(changeset, :rejection_note, "is required when rejecting a location")
    else
      changeset
    end
  end
end
