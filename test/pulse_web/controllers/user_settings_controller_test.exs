defmodule PulseWeb.UserSettingsControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Accounts

  import Pulse.AccountsFixtures

  describe "GET /users/settings" do
    test "renders the account page", %{conn: conn} do
      user = legacy_user_fixture()
      conn = conn |> log_in_user(user) |> get(~p"/users/settings")

      assert html_response(conn, 200) =~ "Account"
    end

    test "redirects an anonymous visitor to log in", %{conn: conn} do
      conn = get(conn, ~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "PUT /users/settings/email" do
    test "adds an email to an account that had none", %{conn: conn} do
      user = legacy_user_fixture()
      refute user.email

      conn =
        conn
        |> log_in_user(user)
        |> put(~p"/users/settings/email", %{"user" => %{"email" => "fresh@example.com", "current_password" => valid_user_password()}})

      assert redirected_to(conn) == ~p"/users/settings"
      assert Accounts.get_user!(user.id).email == "fresh@example.com"
    end

    test "changing a confirmed account's email resets its confirmation", %{conn: conn} do
      user = confirmed_user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> put(~p"/users/settings/email", %{"user" => %{"email" => "changed@example.com", "current_password" => valid_user_password()}})

      assert redirected_to(conn) == ~p"/users/settings"
      updated = Accounts.get_user!(user.id)
      assert updated.email == "changed@example.com"
      refute updated.confirmed_at
    end

    test "re-renders with errors for an invalid email", %{conn: conn} do
      user = legacy_user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> put(~p"/users/settings/email", %{"user" => %{"email" => "not-an-email", "current_password" => valid_user_password()}})

      assert html_response(conn, 200) =~ "must look like an email address"
    end

    test "re-renders with an error and changes nothing for a wrong current password", %{
      conn: conn
    } do
      user = confirmed_user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> put(~p"/users/settings/email", %{
          "user" => %{"email" => "hijacked@example.com", "current_password" => "wrong password"}
        })

      assert html_response(conn, 200) =~ "is not valid"
      assert Accounts.get_user!(user.id).email == user.email
    end
  end

  describe "POST /users/settings/resend_confirmation" do
    test "sends again when there's an unconfirmed email on file", %{conn: conn} do
      user = legacy_user_fixture()
      {:ok, updated} = Accounts.update_user_email(user, valid_user_password(), %{"email" => "fresh@example.com"})

      conn = conn |> log_in_user(updated) |> post(~p"/users/settings/resend_confirmation")

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Confirmation email sent."
    end

    test "says there's nothing to resend when already confirmed", %{conn: conn} do
      user = confirmed_user_fixture()

      conn = conn |> log_in_user(user) |> post(~p"/users/settings/resend_confirmation")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "already confirmed"
    end

    test "says to add an email first when there is none", %{conn: conn} do
      user = legacy_user_fixture()

      conn = conn |> log_in_user(user) |> post(~p"/users/settings/resend_confirmation")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Add an email first"
    end
  end

  defp log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
