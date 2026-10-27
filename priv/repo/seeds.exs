# Seeds a handful of real Lusaka areas/markets with EXAMPLE reports so the
# app has something to show immediately. Mirrors the original Django
# `seed_demo_data` management command's data exactly, so the two versions
# are comparable side by side.
#
#     mix run priv/repo/seeds.exs
#
# Safe to re-run: if the demo reporter already has outage reports, the
# script prints a message and does nothing else (see the guard below —
# this is the same idempotency fix the Django version needed, ported
# here directly rather than rediscovering the same bug).

import Ecto.Query, warn: false

alias Pulse.Repo
alias Pulse.Accounts
alias Pulse.Reports.{Location, OutageReport, PriceReport}

defmodule Seeds do
  def get_or_register_user(username, email, password) do
    case Accounts.get_user_by_username(username) do
      nil ->
        {:ok, user} =
          Accounts.register_user(%{"username" => username, "email" => email, "password" => password})

        user

      user ->
        user
    end
  end

  def get_or_create_location(name, city, type) do
    case Pulse.Repo.get_by(Pulse.Reports.Location, name: name, city: city, location_type: type) do
      nil ->
        {:ok, location} =
          Pulse.Reports.create_location(%{"name" => name, "city" => city, "location_type" => type})

        location

      location ->
        location
    end
  end

  def insert_outage!(location, utility, status, age_seconds, note, reporter) do
    %OutageReport{
      location_id: location.id,
      utility: utility,
      status: status,
      note: note,
      reported_at: ago(age_seconds),
      reported_by_id: reporter.id
    }
    |> Pulse.Repo.insert!()
  end

  def insert_price!(location, commodity, unit, price, age_seconds, reporter) do
    %PriceReport{
      location_id: location.id,
      commodity: commodity,
      unit: unit,
      price_kwacha: Decimal.new(price),
      reported_at: ago(age_seconds),
      reported_by_id: reporter.id
    }
    |> Pulse.Repo.insert!()
  end

  defp ago(seconds) do
    DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)
  end
end

hour = 3600
day = 24 * hour

# A couple of demo accounts so seeded reports have a real author, and you
# have something to log in with immediately. Password is intentionally
# simple — local/demo data only. Emails are placeholder @example.com
# addresses purely so registration's (now required) email field is
# satisfied; they're never actually sent to. These accounts stay
# unconfirmed on purpose — a good way to see the "add/confirm your
# email" settings flow for yourself without touching a real inbox.
reporter = Seeds.get_or_register_user("demo_resident", "demo_resident@example.com", "pulsedemo123")
vendor = Seeds.get_or_register_user("demo_vendor", "demo_vendor@example.com", "pulsedemo123")

already_seeded? = Repo.exists?(from r in OutageReport, where: r.reported_by_id == ^reporter.id)

if already_seeded? do
  IO.puts(
    "Demo data already present — skipping. Delete existing reports first " <>
      "(see README) if you want to reseed."
  )
else
  residential_areas = ["Kabwata", "Chilenje", "Matero", "Kalingalinga", "Chelston"]
  markets = ["Soweto Market", "City Market", "Chilenje Market"]

  locations =
    for name <- residential_areas, into: %{} do
      {name, Seeds.get_or_create_location(name, "Lusaka", Location.residential())}
    end
    |> Map.merge(
      for name <- markets, into: %{} do
        {name, Seeds.get_or_create_location(name, "Lusaka", Location.market())}
      end
    )

  outage_seed = [
    {"Kabwata", OutageReport.electricity(), OutageReport.down(), 1 * hour, "Off since this morning"},
    {"Kabwata", OutageReport.water(), OutageReport.up(), 2 * hour, ""},
    {"Chilenje", OutageReport.electricity(), OutageReport.up(), 30 * 60, ""},
    {"Matero", OutageReport.electricity(), OutageReport.down(), 4 * hour,
     "Load-shedding, expected back by evening"},
    {"Matero", OutageReport.water(), OutageReport.down(), 20 * hour, "Second day of rationing"},
    {"Kalingalinga", OutageReport.water(), OutageReport.up(), 3 * hour, ""},
    {"Chelston", OutageReport.electricity(), OutageReport.down(), 6 * hour, ""}
  ]

  for {area, utility, status, age, note} <- outage_seed do
    Seeds.insert_outage!(locations[area], utility, status, age, note, reporter)
  end

  # Illustrative prices in the range reported by JCTR's June 2026 Basic Needs
  # Basket update (charcoal K725 -> K900 per 90kg bag over H1 2026).
  price_seed = [
    {"Soweto Market", PriceReport.mealie_meal(), "25kg bag", "295.00", 1 * day},
    {"Soweto Market", PriceReport.charcoal(), "90kg bag", "900.00", 1 * day},
    {"Soweto Market", PriceReport.charcoal(), "90kg bag", "875.00", 30 * day},
    {"City Market", PriceReport.kapenta(), "kg", "180.00", 2 * day},
    {"City Market", PriceReport.cooking_oil(), "2 litre", "145.00", 2 * day},
    {"Chilenje Market", PriceReport.mealie_meal(), "25kg bag", "310.00", 12 * hour},
    {"Chilenje Market", PriceReport.tomatoes(), "kg", "25.00", 12 * hour}
  ]

  for {market, commodity, unit, price, age} <- price_seed do
    Seeds.insert_price!(locations[market], commodity, unit, price, age, vendor)
  end

  IO.puts(
    "Seeded #{map_size(locations)} locations, 2 demo users " <>
      "(login: demo_resident / demo_vendor, password: pulsedemo123), " <>
      "#{Repo.aggregate(OutageReport, :count)} outage reports, " <>
      "#{Repo.aggregate(PriceReport, :count)} price reports."
  )
end
