defmodule PulseWeb.LocationControllerTest do
  use PulseWeb.ConnCase, async: true

  import Pulse.AccountsFixtures

  alias Pulse.Accounts
  alias Pulse.Reports

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "a logged-out visitor is sent to log in" do
    conn = get(build_conn(), ~p"/locations/new")
    assert redirected_to(conn) == ~p"/users/log_in"
  end

  test "renders the form with the city filled in", %{conn: conn} do
    html = conn |> get(~p"/locations/new") |> html_response(200)

    assert html =~ "Propose a location"
    assert html =~ ~s(value="Lusaka")
  end

  test "submits a location for review", %{conn: conn, user: user} do
    conn =
      post(conn, ~p"/locations", %{
        "location" => %{"name" => "Chawama", "city" => "Lusaka", "location_type" => "residential"}
      })

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "submitted for review"

    assert [%{name: "Chawama", status: "pending", submitted_by_id: user_id}] =
             Reports.list_pending_locations()

    assert user_id == user.id
    refute "Chawama" in Enum.map(Reports.list_locations(), & &1.name)
  end

  test "re-renders with errors and keeps what was typed", %{conn: conn} do
    conn =
      post(conn, ~p"/locations", %{
        "location" => %{"name" => "Chawama", "city" => "Lusaka", "location_type" => ""}
      })

    html = html_response(conn, 200)
    assert html =~ "can&#39;t be blank"
    assert html =~ ~s(value="Chawama")
    assert Reports.list_pending_locations() == []
  end

  test "quietly drops a submission that fills in the honeypot", %{conn: conn} do
    conn =
      post(conn, ~p"/locations", %{
        "location" => %{
          "name" => "Spamville",
          "city" => "Lusaka",
          "location_type" => "residential",
          "website" => "http://spam.example"
        }
      })

    assert redirected_to(conn) == ~p"/"
    assert Reports.list_pending_locations() == []
  end

  defp log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
