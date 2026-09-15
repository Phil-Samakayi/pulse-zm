defmodule Pulse.Reports.Location do
  use Ecto.Schema
  import Ecto.Changeset

  @residential "residential"
  @market "market"

  def residential, do: @residential
  def market, do: @market
  def location_types, do: [@residential, @market]

  schema "locations" do
    field :name, :string
    field :city, :string, default: "Lusaka"
    field :location_type, :string

    has_many :outage_reports, Pulse.Reports.OutageReport
    has_many :price_reports, Pulse.Reports.PriceReport

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :city, :location_type])
    |> validate_required([:name, :city, :location_type])
    |> validate_inclusion(:location_type, location_types())
    |> unique_constraint([:name, :city, :location_type])
  end
end
