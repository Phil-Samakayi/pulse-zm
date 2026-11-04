defmodule PulseWeb.ReportControllerTest do
  use PulseWeb.ConnCase, async: true

  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  alias Pulse.Accounts
  alias Pulse.Reports

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user, location: location_fixture()}
  end

  describe "logged out" do
    test "the report pages send a visitor to log in", %{location: location} do
      conn = get(build_conn(), ~p"/locations/#{location.id}/report/outage")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "one-tap outage buttons" do
    test "record the report and go back to the location page", %{
      conn: conn,
      user: user,
      location: location
    } do
      conn =
        post(conn, ~p"/locations/#{location.id}/outages", %{
          "outage_report" => %{"utility" => "electricity", "status" => "down"}
        })

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "your report is in"

      assert [%{utility: "electricity", status: "down", reported_by_id: user_id}] =
               Reports.location_status(location).latest_outages

      assert user_id == user.id
    end

    test "a second tap within the cooldown comes back as a flash, not a crash", %{
      conn: conn,
      location: location
    } do
      params = %{"outage_report" => %{"utility" => "water", "status" => "up"}}
      post(conn, ~p"/locations/#{location.id}/outages", params)

      conn = post(conn, ~p"/locations/#{location.id}/outages", params)

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already reported this"
    end
  end

  describe "outage form" do
    test "renders", %{conn: conn, location: location} do
      conn = get(conn, ~p"/locations/#{location.id}/report/outage")
      assert html_response(conn, 200) =~ "Report power or water"
    end

    test "saves a report with a note", %{conn: conn, location: location} do
      conn =
        post(conn, ~p"/locations/#{location.id}/outages", %{
          "source" => "form",
          "outage_report" => %{
            "utility" => "electricity",
            "status" => "down",
            "note" => "Off since 6am"
          }
        })

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert [%{note: "Off since 6am"}] = Reports.location_status(location).latest_outages
    end

    test "re-renders with errors and keeps what was typed", %{conn: conn, location: location} do
      conn =
        post(conn, ~p"/locations/#{location.id}/outages", %{
          "source" => "form",
          "outage_report" => %{"utility" => "electricity", "note" => "Off since 6am"}
        })

      html = html_response(conn, 200)
      assert html =~ "can&#39;t be blank"
      assert html =~ "Off since 6am"
      assert Reports.location_status(location).latest_outages == []
    end

    test "quietly drops a submission that fills in the honeypot", %{
      conn: conn,
      location: location
    } do
      conn =
        post(conn, ~p"/locations/#{location.id}/outages", %{
          "source" => "form",
          "outage_report" => %{
            "utility" => "electricity",
            "status" => "down",
            "website" => "http://spam.example"
          }
        })

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert Reports.location_status(location).latest_outages == []
    end
  end

  describe "price form" do
    test "renders", %{conn: conn, location: location} do
      conn = get(conn, ~p"/locations/#{location.id}/report/price")
      assert html_response(conn, 200) =~ "Report a price"
    end

    test "saves a price", %{conn: conn, location: location} do
      conn =
        post(conn, ~p"/locations/#{location.id}/prices", %{
          "price_report" => %{
            "commodity" => "mealie_meal",
            "unit" => "25kg bag",
            "price_kwacha" => "450"
          }
        })

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert [%{commodity: "mealie_meal"}] = Reports.location_status(location).latest_prices
    end

    test "sets a standard item's unit itself", %{conn: conn, location: location} do
      post(conn, ~p"/locations/#{location.id}/prices", %{
        "price_report" => %{"commodity" => "cooking_oil", "price_kwacha" => "126"}
      })

      assert [%{unit: "2.5 litres"}] = Reports.location_status(location).latest_prices
    end

    test "re-renders with errors", %{conn: conn, location: location} do
      conn =
        post(conn, ~p"/locations/#{location.id}/prices", %{
          "price_report" => %{"commodity" => "mealie_meal", "unit" => "", "price_kwacha" => ""}
        })

      assert html_response(conn, 200) =~ "can&#39;t be blank"
      assert Reports.location_status(location).latest_prices == []
    end
  end

  describe "flagging" do
    setup %{location: location} do
      reporter = user_fixture()

      {:ok, report} =
        Reports.create_outage_report(
          valid_outage_attrs(location_id: location.id, reported_by_id: reporter.id)
        )

      %{report: report}
    end

    test "shows the report being flagged", %{conn: conn, location: location, report: report} do
      conn = get(conn, ~p"/locations/#{location.id}/flag/outage/#{report.id}")
      assert html_response(conn, 200) =~ "Power out"
    end

    test "flags it for review", %{conn: conn, location: location, report: report} do
      conn =
        post(conn, ~p"/locations/#{location.id}/flag/outage/#{report.id}", %{
          "flag" => %{"reason" => "Power is back"}
        })

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert [%{id: id, flag_reason: "Power is back"}] = Reports.list_flagged_reports().outages
      assert id == report.id
    end

    test "won't flag a report from another location through this one's URL", %{
      conn: conn,
      report: report
    } do
      other = location_fixture()

      conn =
        post(conn, ~p"/locations/#{other.id}/flag/outage/#{report.id}", %{
          "flag" => %{"reason" => "x"}
        })

      assert redirected_to(conn) == ~p"/locations/#{other.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "couldn't be found"
      assert Reports.list_flagged_reports().outages == []
    end
  end

  describe "locations that aren't public" do
    test "can't be reported at by a regular user", %{conn: conn, user: user} do
      {:ok, pending} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))

      conn =
        post(conn, ~p"/locations/#{pending.id}/outages", %{
          "outage_report" => %{"utility" => "electricity", "status" => "down"}
        })

      assert redirected_to(conn) == ~p"/"
      assert Reports.location_status(pending).latest_outages == []
    end
  end

  defp log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
