defmodule Pulse.Reports.PriceReport do
  use Ecto.Schema
  import Ecto.Changeset

  @mealie_meal "mealie_meal"
  @charcoal "charcoal"
  @kapenta "kapenta"
  @cooking_oil "cooking_oil"
  @tomatoes "tomatoes"
  @other "other"

  def mealie_meal, do: @mealie_meal
  def charcoal, do: @charcoal
  def kapenta, do: @kapenta
  def cooking_oil, do: @cooking_oil
  def tomatoes, do: @tomatoes
  def other, do: @other

  def commodities, do: [@mealie_meal, @charcoal, @kapenta, @cooking_oil, @tomatoes, @other]

  def commodity_label(@mealie_meal), do: "Mealie meal"
  def commodity_label(@charcoal), do: "Charcoal"
  def commodity_label(@kapenta), do: "Kapenta"
  def commodity_label(@cooking_oil), do: "Cooking oil"
  def commodity_label(@tomatoes), do: "Tomatoes"
  def commodity_label(@other), do: "Other"

  schema "price_reports" do
    belongs_to :location, Pulse.Reports.Location
    field :commodity, :string
    field :commodity_other, :string, default: ""
    field :unit, :string
    field :price_kwacha, :decimal
    field :note, :string, default: ""
    field :reported_at, :utc_datetime
    belongs_to :reported_by, Pulse.Accounts.User
    field :is_flagged, :boolean, default: false
    field :flag_reason, :string, default: ""

    # Honeypot — see Pulse.Reports.Location for why this exists and why
    # it's `virtual: true`. Bound in LocationLive.Show's price form.
    field :website, :string, virtual: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "See OutageReport.changeset/2 for why reported_at is always set here, never accepted."
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :location_id,
      :commodity,
      :commodity_other,
      :unit,
      :price_kwacha,
      :note,
      :reported_by_id,
      :website
    ])
    |> validate_required([:location_id, :commodity, :unit, :price_kwacha])
    |> validate_inclusion(:commodity, commodities())
    |> validate_number(:price_kwacha, greater_than: 0)
    |> validate_length(:note, max: 280)
    |> validate_length(:commodity_other, max: 80)
    |> validate_other_commodity()
    |> put_change(:reported_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:location_id)
  end

  defp validate_other_commodity(changeset) do
    if get_field(changeset, :commodity) == @other and
         (get_field(changeset, :commodity_other) || "") == "" do
      add_error(changeset, :commodity_other, "is required when commodity is \"Other\"")
    else
      changeset
    end
  end

  def flag_changeset(report, attrs) do
    report
    |> cast(attrs, [:is_flagged, :flag_reason])
    |> validate_length(:flag_reason, max: 280)
  end
end
