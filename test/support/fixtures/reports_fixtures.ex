defmodule Pulse.ReportsFixtures do
  @moduledoc """
  Helpers for creating `Pulse.Reports` entities in tests.
  """

  alias Pulse.Reports
  alias Pulse.Reports.Location

  def unique_location_name, do: "Location #{System.unique_integer([:positive])}"

  def valid_location_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_location_name(),
      city: "Lusaka",
      location_type: Location.residential()
    })
  end

  @doc "Inserts a pre-approved location directly, bypassing submission/review — mirrors seeds.exs."
  def location_fixture(attrs \\ %{}) do
    {:ok, location} = attrs |> valid_location_attrs() |> Reports.create_location()
    location
  end

  def valid_outage_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      utility: "electricity",
      status: "down",
      note: ""
    })
  end

  def valid_price_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      commodity: "mealie_meal",
      unit: "25kg bag",
      price_kwacha: "450.00"
    })
  end
end
