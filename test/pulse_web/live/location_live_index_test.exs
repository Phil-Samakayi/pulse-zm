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

  test "shows how many people are behind a status", %{conn: conn} do
    location = location_fixture()

    for _ <- 1..2 do
      {:ok, _} =
        Reports.create_outage_report(
          valid_outage_attrs(location_id: location.id, reported_by_id: user_fixture().id)
        )
    end

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "2 people"
  end

  test "says so when a location has no reports yet", %{conn: conn} do
    location_fixture()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "No reports yet"
  end

  test "a row whose reports are all old says so instead of listing them", %{conn: conn} do
    location = location_fixture(name: "Chilenje")

    %Pulse.Reports.OutageReport{
      location_id: location.id,
      utility: "electricity",
      status: "up",
      reported_at: DateTime.utc_now() |> DateTime.add(-10 * 24 * 60 * 60) |> DateTime.truncate(:second)
    }
    |> Pulse.Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "No recent reports · last report"
    refute html =~ "Power on"
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
