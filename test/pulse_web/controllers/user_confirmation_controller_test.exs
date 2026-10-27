defmodule PulseWeb.UserConfirmationControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Accounts

  import Pulse.AccountsFixtures

  describe "GET /users/confirm/:token" do
    test "confirms the account and redirects home", %{conn: conn} do
      user = user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_confirmation_instructions(user, url_fun)
        end)

      conn = get(conn, ~p"/users/confirm/#{token}")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Email confirmed"
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "rejects an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/confirm/not-a-real-token")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end

    test "rejects a token that's already been used", %{conn: conn} do
      user = user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_confirmation_instructions(user, url_fun)
        end)

      get(conn, ~p"/users/confirm/#{token}")
      conn = get(conn, ~p"/users/confirm/#{token}")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end
end
