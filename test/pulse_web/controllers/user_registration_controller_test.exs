defmodule PulseWeb.UserRegistrationControllerTest do
  use PulseWeb.ConnCase, async: true

  import Pulse.AccountsFixtures

  describe "GET /users/register" do
    test "renders the registration form", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Create an account"
    end

    test "redirects an already-logged-in user to the home page", %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user) |> get(~p"/users/register")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/register" do
    test "creates an account with valid data and redirects to log in", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attrs(username: "brandnewuser")
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Pulse.Accounts.get_user_by_username("brandnewuser")
    end

    test "re-renders the form with errors on invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"username" => "no", "password" => "short"}
        })

      response = html_response(conn, 200)
      assert response =~ "Oops, something went wrong"
    end

    test "re-renders the form when the username is already taken", %{conn: conn} do
      %{username: username} = user_fixture()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attrs(username: username)
        })

      response = html_response(conn, 200)
      assert response =~ "Oops, something went wrong"
    end
  end

  defp log_in_user(conn, user) do
    token = Pulse.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
