defmodule PulseWeb.UserForgotPasswordControllerTest do
  use PulseWeb.ConnCase, async: true

  import Pulse.AccountsFixtures

  describe "GET /users/reset_password" do
    test "renders the request form", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password")
      assert html_response(conn, 200) =~ "Forgot your password?"
    end
  end

  describe "POST /users/reset_password" do
    test "shows the same message for a confirmed account", %{conn: conn} do
      user = confirmed_user_fixture()

      conn = post(conn, ~p"/users/reset_password", %{"user" => %{"email" => user.email}})

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "we've sent reset instructions"
    end

    test "shows the same message for an unknown email (doesn't leak which emails exist)", %{
      conn: conn
    } do
      conn = post(conn, ~p"/users/reset_password", %{"user" => %{"email" => "nobody@example.com"}})

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "we've sent reset instructions"
    end

    test "shows the same message for an unconfirmed account", %{conn: conn} do
      user = user_fixture()

      conn = post(conn, ~p"/users/reset_password", %{"user" => %{"email" => user.email}})

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "we've sent reset instructions"
    end
  end
end
