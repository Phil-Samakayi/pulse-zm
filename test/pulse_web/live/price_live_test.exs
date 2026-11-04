defmodule PulseWeb.PriceLiveTest do
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  alias Pulse.Reports

  setup do
    user = user_fixture()
    cheap = location_fixture(name: "Cheap Market")
    dear = location_fixture(name: "Dear Market")

    for {location, price} <- [{dear, "450.00"}, {cheap, "420.00"}] do
      {:ok, _} =
        Reports.create_price_report(
          valid_price_attrs(location_id: location.id, reported_by_id: user.id, price_kwacha: price)
        )
    end

    %{cheap: cheap, dear: dear}
  end

  describe "Compare prices" do
    test "shows each item's cheapest place and the range", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/prices")

      assert html =~ "Mealie meal (25kg bag)"
      assert html =~ "Cheapest"
      assert html =~ "K420.00"
      assert html =~ "Cheap Market"
      assert html =~ "across 2 places"
    end

    test "says so for an item with no recent prices", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/prices")

      assert html =~ "Onions (pile)"
      assert html =~ "No prices in the last two weeks"
    end

    test "is linked from the home page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ ~s(href="/prices")
    end
  end

  describe "an item's page" do
    test "ranks every place cheapest first, with the difference", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/prices/mealie_meal")

      {cheap_at, _} = :binary.match(html, "Cheap Market")
      {dear_at, _} = :binary.match(html, "Dear Market")

      assert cheap_at < dear_at
      assert html =~ "Cheapest"
      assert html =~ "+K30"
    end

    test "has a WhatsApp share of the list", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/prices/mealie_meal")

      assert html =~ "https://wa.me/?text=%2AMealie%20meal%20%2825kg%20bag%29%2A"
    end

    test "an unknown item goes back to Compare prices", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/prices"}}} = live(conn, ~p"/prices/caviar")
    end
  end
end
