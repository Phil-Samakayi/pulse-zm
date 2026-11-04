defmodule PulseWeb.LocationLive.ShowTest do
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  alias Pulse.Accounts
  alias Pulse.Reports

  setup do
    location = location_fixture(name: "Kabwata")
    reporter = user_fixture()

    {:ok, _} =
      Reports.create_outage_report(
        valid_outage_attrs(
          location_id: location.id,
          reported_by_id: reporter.id,
          utility: "electricity",
          status: "down",
          note: "Off since this morning"
        )
      )

    %{location: location, reporter: reporter}
  end

  test "shows the latest reports in the same words as the home page", %{
    conn: conn,
    location: location,
    reporter: reporter
  } do
    {:ok, _view, html} = live(conn, ~p"/locations/#{location.id}")

    assert html =~ "Kabwata"
    assert html =~ "Power is"
    assert html =~ "out"
    assert html =~ "Off since this morning"
    assert html =~ "#{reporter.username} · just now"
    refute html =~ "Electricity is"
  end

  test "a logged-out visitor is asked to log in or sign up to report", %{
    conn: conn,
    location: location
  } do
    {:ok, _view, html} = live(conn, ~p"/locations/#{location.id}")

    assert html =~ "to report what&#39;s happening here"
    refute html =~ "What&#39;s happening here right now?"
  end

  test "a logged-in user gets the one-tap buttons, posting to the report controller", %{
    conn: conn,
    location: location
  } do
    {:ok, _view, html} = conn |> log_in_user(user_fixture()) |> live(~p"/locations/#{location.id}")

    assert html =~ "What&#39;s happening here right now?"
    assert html =~ ~s(action="/locations/#{location.id}/outages")
    assert html =~ "Water on"
    assert html =~ "Report a price"
  end

  test "shows how long the status has held and how many people reported it", %{
    conn: conn,
    location: location
  } do
    {:ok, _} =
      Reports.create_outage_report(
        valid_outage_attrs(
          location_id: location.id,
          reported_by_id: user_fixture().id,
          utility: "electricity",
          status: "down"
        )
      )

    {:ok, _view, html} = live(conn, ~p"/locations/#{location.id}")

    assert html =~ "Since"
    assert html =~ "reported by 2 people"
  end

  test "offers Me too to someone who hasn't reported, and not to the reporter", %{
    conn: conn,
    location: location,
    reporter: reporter
  } do
    {:ok, _view, html} = conn |> log_in_user(user_fixture()) |> live(~p"/locations/#{location.id}")
    assert html =~ "Me too"

    {:ok, _view, html} = build_conn() |> log_in_user(reporter) |> live(~p"/locations/#{location.id}")
    assert html =~ "You reported this"
    refute html =~ "Me too"
  end

  test "a logged-in user can turn on alerts for the place, and then sees them on", %{
    conn: conn,
    location: location
  } do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, ~p"/locations/#{location.id}")
    assert html =~ "Get alerts for Kabwata"
    assert html =~ ~s(action="/alerts/locations/#{location.id}")
    assert html =~ "data-needs-push"

    {:ok, _} = Pulse.Alerts.follow_location(user, location)

    {:ok, _view, html} = live(conn, ~p"/locations/#{location.id}")
    assert html =~ "Alerts on"
    assert html =~ "Turn off"
    refute html =~ "Get alerts for"
  end

  test "has a WhatsApp share link with the location's summary", %{conn: conn, location: location} do
    {:ok, _view, html} = live(conn, ~p"/locations/#{location.id}")

    assert html =~ "https://wa.me/?text=%2AKabwata%2A"
    assert html =~ "Power%20out"
  end

  test "a pending location isn't shown to a regular user", %{conn: conn} do
    pending = Reports.submit_location(valid_location_attrs(submitted_by_id: user_fixture().id))
    {:ok, pending} = pending

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/locations/#{pending.id}")
  end

  defp log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
