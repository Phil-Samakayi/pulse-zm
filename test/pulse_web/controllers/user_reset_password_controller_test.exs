defmodule PulseWeb.UserResetPasswordControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Accounts

  import Pulse.AccountsFixtures

  describe "GET /users/reset_password/:token" do
    test "renders the new-password form for a valid token", %{conn: conn} do
      user = confirmed_user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_reset_password_instructions(user, url_fun)
        end)

      conn = get(conn, ~p"/users/reset_password/#{token}")
      assert html_response(conn, 200) =~ "Set a new password"
    end

    test "redirects for an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password/not-a-real-token")

      assert redirected_to(conn) == ~p"/users/reset_password"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end

  describe "POST /users/reset_password/:token" do
    test "resets the password with a valid token and new password", %{conn: conn} do
      user = confirmed_user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_reset_password_instructions(user, url_fun)
        end)

      conn =
        post(conn, ~p"/users/reset_password/#{token}", %{
          "user" => %{"password" => "a-new-password"}
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Accounts.get_user_by_username_and_password(user.username, "a-new-password")
    end

    test "re-renders with errors for a too-short password", %{conn: conn} do
      user = confirmed_user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_reset_password_instructions(user, url_fun)
        end)

      conn = post(conn, ~p"/users/reset_password/#{token}", %{"user" => %{"password" => "short"}})

      assert html_response(conn, 200) =~ "should be at least 8 character"
    end

    test "redirects for an invalid token", %{conn: conn} do
      conn =
        post(conn, ~p"/users/reset_password/not-a-real-token", %{
          "user" => %{"password" => "a-new-password"}
        })

      assert redirected_to(conn) == ~p"/users/reset_password"
    end
  end
end
