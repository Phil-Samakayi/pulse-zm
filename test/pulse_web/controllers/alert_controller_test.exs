defmodule PulseWeb.AlertControllerTest do
  use PulseWeb.ConnCase, async: true

  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  alias Pulse.Accounts
  alias Pulse.Alerts
  alias Pulse.Alerts.PushSubscription
  alias Pulse.Repo
  alias Pulse.Reports

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user, location: location_fixture(name: "Matero")}
  end

  describe "saving a browser's subscription" do
    test "stores it and answers in JSON", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/alerts/subscriptions",
          Jason.encode!(%{
            endpoint: "https://push.example/phone",
            expirationTime: nil,
            keys: %{p256dh: "public-key", auth: "secret"}
          })
        )

      assert json_response(conn, 200) == %{"ok" => true}
      assert [%{endpoint: "https://push.example/phone", user_id: user_id}] = Repo.all(PushSubscription)
      assert user_id == user.id
    end

    test "says no to something that isn't a subscription", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/alerts/subscriptions", Jason.encode!(%{endpoint: "x"}))

      assert json_response(conn, 422) == %{"ok" => false}
      assert Repo.all(PushSubscription) == []
    end
  end

  describe "following a location" do
    test "turns alerts on and goes back to the place", %{conn: conn, user: user, location: location} do
      conn = post(conn, ~p"/alerts/locations/#{location.id}")

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Alerts on for Matero"
      assert Alerts.following_location?(user, location.id)
    end

    test "turning them on twice is fine", %{conn: conn, location: location} do
      post(conn, ~p"/alerts/locations/#{location.id}")
      conn = post(conn, ~p"/alerts/locations/#{location.id}")

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Alerts on"
    end

    test "turns them off", %{conn: conn, user: user, location: location} do
      {:ok, _} = Alerts.follow_location(user, location)

      conn = delete(conn, ~p"/alerts/locations/#{location.id}")

      assert redirected_to(conn) == ~p"/locations/#{location.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Alerts off for Matero"
      refute Alerts.following_location?(user, location.id)
    end

    test "not for a place that isn't public yet", %{conn: conn, user: user} do
      {:ok, pending} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))

      conn = post(conn, ~p"/alerts/locations/#{pending.id}")

      assert redirected_to(conn) == ~p"/"
      refute Alerts.following_location?(user, pending.id)
    end

    test "a logged-out visitor is sent to log in", %{location: location} do
      conn = post(build_conn(), ~p"/alerts/locations/#{location.id}")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  defp log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
