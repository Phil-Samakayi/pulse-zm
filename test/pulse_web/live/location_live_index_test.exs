defmodule PulseWeb.LocationLive.IndexTest do
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  alias Pulse.Reports

  test "shows each location's latest status on its row", %{conn: conn} do
    location = location_fixture(name: "Chilenje")
    user = user_fixture()

    {:ok, _} =
      Reports.create_outage_report(
        valid_outage_attrs(
          location_id: location.id,
          reported_by_id: user.id,
          utility: "electricity",
          status: "down"
        )
      )

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Chilenje"
    assert html =~ "Power out"
    assert html =~ "just now"
  end

  test "says so when a location has no reports yet", %{conn: conn} do
    location_fixture()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "No reports yet"
  end

  test "updates a row live when someone reports there", %{conn: conn} do
    location = location_fixture()
    user = user_fixture()

    {:ok, view, html} = live(conn, ~p"/")
    refute html =~ "Water out"

    {:ok, _} =
      Reports.create_outage_report(
        valid_outage_attrs(
          location_id: location.id,
          reported_by_id: user.id,
          utility: "water",
          status: "down"
        )
      )

    assert render(view) =~ "Water out"
  end
end
