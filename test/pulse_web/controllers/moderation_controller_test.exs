defmodule PulseWeb.ModerationControllerTest do
  use PulseWeb.ConnCase, async: true

  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  alias Pulse.Accounts
  alias Pulse.Reports

  setup %{conn: conn} do
    submitter = user_fixture()
    {:ok, pending} = Reports.submit_location(valid_location_attrs(submitted_by_id: submitter.id))

    %{conn: log_in_user(conn, admin_fixture()), pending: pending}
  end

  describe "access" do
    test "a logged-out visitor is sent to log in" do
      conn = get(build_conn(), ~p"/moderation")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "a regular user is sent home" do
      conn = build_conn() |> log_in_user(user_fixture()) |> get(~p"/moderation")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "don't have access"
    end

    test "a regular user can't approve through the POST route either", %{pending: pending} do
      conn =
        build_conn()
        |> log_in_user(user_fixture())
        |> post(~p"/moderation/locations/#{pending.id}/approve")

      assert redirected_to(conn) == ~p"/"
      assert Reports.get_location!(pending.id).status == "pending"
    end
  end

  test "an admin sees the queue", %{conn: conn, pending: pending} do
    html = conn |> get(~p"/moderation") |> html_response(200)

    assert html =~ "Moderation queue"
    assert html =~ pending.name
  end

  describe "pending locations" do
    test "approve makes the location public", %{conn: conn, pending: pending} do
      conn = post(conn, ~p"/moderation/locations/#{pending.id}/approve")

      assert redirected_to(conn) == ~p"/moderation"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "approved"
      assert pending.name in Enum.map(Reports.list_locations(), & &1.name)
    end

    test "the reject page asks for a reason", %{conn: conn, pending: pending} do
      html = conn |> get(~p"/moderation/locations/#{pending.id}/reject") |> html_response(200)
      assert html =~ "Why is this being rejected?"
    end

    test "reject with a reason saves it", %{conn: conn, pending: pending} do
      conn =
        post(conn, ~p"/moderation/locations/#{pending.id}/reject", %{
          "reject" => %{"reason" => "Duplicate of Kabwata"}
        })

      assert redirected_to(conn) == ~p"/moderation"
      rejected = Reports.get_location!(pending.id)
      assert rejected.status == "rejected"
      assert rejected.rejection_note == "Duplicate of Kabwata"
    end

    test "reject without a reason re-renders with an error", %{conn: conn, pending: pending} do
      conn =
        post(conn, ~p"/moderation/locations/#{pending.id}/reject", %{"reject" => %{"reason" => "  "}})

      assert html_response(conn, 200) =~ "is required when rejecting a location"
      assert Reports.get_location!(pending.id).status == "pending"
    end

    test "acting on something no longer pending says so", %{conn: conn, pending: pending} do
      {:ok, _} = Reports.approve_location(pending)

      conn = post(conn, ~p"/moderation/locations/#{pending.id}/approve")

      assert redirected_to(conn) == ~p"/moderation"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no longer in the queue"
    end
  end

  describe "flagged reports" do
    setup do
      location = location_fixture()
      reporter = user_fixture()

      {:ok, outage} =
        Reports.create_outage_report(
          valid_outage_attrs(location_id: location.id, reported_by_id: reporter.id)
        )

      {:ok, price} =
        Reports.create_price_report(
          valid_price_attrs(location_id: location.id, reported_by_id: reporter.id)
        )

      {:ok, outage} = Reports.flag_outage_report(outage, %{"flag_reason" => "Power is back"})
      {:ok, price} = Reports.flag_price_report(price, %{"flag_reason" => "Too high"})

      %{outage: outage, price: price}
    end

    test "show in the queue with their reasons", %{conn: conn} do
      html = conn |> get(~p"/moderation") |> html_response(200)

      assert html =~ "Power is back"
      assert html =~ "Too high"
    end

    test "clear flag removes an outage report from the queue", %{conn: conn, outage: outage} do
      conn = post(conn, ~p"/moderation/flags/outage/#{outage.id}/clear")

      assert redirected_to(conn) == ~p"/moderation"
      assert Reports.list_flagged_reports().outages == []
    end

    test "clear flag removes a price report from the queue", %{conn: conn, price: price} do
      conn = post(conn, ~p"/moderation/flags/price/#{price.id}/clear")

      assert redirected_to(conn) == ~p"/moderation"
      assert Reports.list_flagged_reports().prices == []
    end
  end

  defp log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
