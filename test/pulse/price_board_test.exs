defmodule Pulse.PriceBoardTest do
  use Pulse.DataCase, async: true

  alias Pulse.Reports

  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  describe "price_board/1" do
    test "lists the latest price at each location, cheapest first" do
      [a, b, c] = for _ <- 1..3, do: location_fixture()

      insert_price!(a, price: "480", minutes_ago: 120)
      insert_price!(a, price: "470", minutes_ago: 10)
      insert_price!(b, price: "420", minutes_ago: 60)
      insert_price!(c, price: "450", minutes_ago: 30)

      board = Reports.price_board()

      assert Enum.map(board["mealie_meal"], &{&1.location_id, Decimal.to_string(&1.price_kwacha)}) ==
               [{b.id, "420"}, {c.id, "450"}, {a.id, "470"}]

      assert hd(board["mealie_meal"]).location.id == b.id
    end

    test "only compares like for like" do
      [kg_tomatoes, flagged, old, good] = for _ <- 1..4, do: location_fixture()

      {:ok, pending} =
        Reports.submit_location(valid_location_attrs(submitted_by_id: user_fixture().id))

      insert_price!(kg_tomatoes, commodity: "tomatoes", unit: "kg", minutes_ago: 5)
      insert_price!(flagged, price: "100", flagged: true, minutes_ago: 5)
      insert_price!(old, price: "200", minutes_ago: 20 * 24 * 60)
      insert_price!(pending, price: "300", minutes_ago: 5)
      insert_price!(good, price: "460", minutes_ago: 5)

      board = Reports.price_board()

      refute Map.has_key?(board, "tomatoes")
      assert Enum.map(board["mealie_meal"], & &1.location_id) == [good.id]
    end
  end

  defp minutes_ago(minutes) do
    DateTime.utc_now() |> DateTime.add(-minutes * 60) |> DateTime.truncate(:second)
  end

  # Inserted directly rather than through create_price_report/1, which
  # always stamps reported_at with "now" and forces the standard unit —
  # these tests need control over both.
  defp insert_price!(location, opts) do
    %Pulse.Reports.PriceReport{
      location_id: location.id,
      commodity: Keyword.get(opts, :commodity, "mealie_meal"),
      unit: Keyword.get(opts, :unit, "25kg bag"),
      price_kwacha: Decimal.new(Keyword.get(opts, :price, "450.00")),
      reported_at: minutes_ago(Keyword.fetch!(opts, :minutes_ago)),
      is_flagged: Keyword.get(opts, :flagged, false)
    }
    |> Pulse.Repo.insert!()
  end
end
