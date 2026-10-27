defmodule PulseWeb.UserSessionControllerTest do
  use PulseWeb.ConnCase, async: true

  import Pulse.AccountsFixtures

  setup do
    %{user: user_fixture(password: "correcthorsebattery")}
  end

  describe "GET /users/log_in" do
    test "renders the login form", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in")
      response = html_response(conn, 200)
      assert response =~ "Log in"
    end

    test "redirects an already-logged-in user to the home page", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/users/log_in")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/log_in" do
    test "logs the user in with valid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"username" => user.username, "password" => "correcthorsebattery"}
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end

    test "sets a remember-me cookie when asked", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "username" => user.username,
            "password" => "correcthorsebattery",
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_pulse_web_user_remember_me"]
    end

    test "rejects an invalid password", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"username" => user.username, "password" => "wrong password"}
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid username or password"
    end

    test "rejects an unknown username", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"username" => "nobody", "password" => "whatever123"}
        })

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out and invalidates the session token", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      token = get_session(conn, :user_token)

      conn = delete(conn, ~p"/users/log_out")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      refute Pulse.Accounts.get_user_by_session_token(token)
    end

    test "is a no-op when already logged out", %{conn: conn} do
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
    end
  end

  defp log_in_user(conn, user) do
    token = Pulse.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
