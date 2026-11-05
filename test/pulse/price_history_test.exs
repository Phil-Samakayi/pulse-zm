defmodule Pulse.PriceHistoryTest do
  use Pulse.DataCase, async: true

  import Pulse.ReportsFixtures

  alias Pulse.Reports
  alias Pulse.Reports.PriceReport

  defp days_ago(n),
    do: DateTime.utc_now() |> DateTime.add(-n * 24 * 60 * 60, :second) |> DateTime.truncate(:second)

  defp insert!(location, attrs) do
    struct(
      %PriceReport{
        location_id: location.id,
        commodity: "mealie_meal",
        unit: "25kg bag",
        price_kwacha: Decimal.new("300.00"),
        reported_at: days_ago(3)
      },
      attrs
    )
    |> Repo.insert!()
  end

  test "lists an item's standard-unit prices since a date, oldest first" do
    market = location_fixture(name: "Soweto Market")
    older = insert!(market, reported_at: days_ago(20))
    newer = insert!(market, reported_at: days_ago(2))

    assert [first, second] = Reports.price_history("mealie_meal", days_ago(30))
    assert {first.id, second.id} == {older.id, newer.id}
    assert first.location.name == "Soweto Market"
  end

  test "leaves out flagged reports, other units, other items and older prices" do
    market = location_fixture()
    insert!(market, is_flagged: true)
    insert!(market, unit: "25kg")
    insert!(market, commodity: "cooking_oil", unit: "2.5 litres")
    insert!(market, reported_at: days_ago(40))

    assert Reports.price_history("mealie_meal", days_ago(30)) == []
  end
end
