defmodule PulseWeb.UserResetPasswordController do
  use PulseWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Pulse.Accounts

  @doc "Renders the 'set a new password' form if the token is still valid."
  def new(conn, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      changeset = Accounts.change_user_password(user)
      render(conn, :new, form: to_form(changeset, as: "user"), token: token)
    else
      conn
      |> put_flash(:error, "That reset link is invalid or has expired.")
      |> redirect(to: ~p"/users/reset_password")
    end
  end

  @doc "Handles the new-password form POST."
  def create(conn, %{"token" => token, "user" => user_params}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      case Accounts.reset_user_password(user, user_params) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Password reset — please log in with your new password.")
          |> redirect(to: ~p"/users/log_in")

        {:error, changeset} ->
          render(conn, :new, form: to_form(changeset, as: "user"), token: token)
      end
    else
      conn
      |> put_flash(:error, "That reset link is invalid or has expired.")
      |> redirect(to: ~p"/users/reset_password")
    end
  end
end
