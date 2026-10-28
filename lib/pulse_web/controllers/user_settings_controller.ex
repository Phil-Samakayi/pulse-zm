defmodule PulseWeb.UserSettingsController do
  use PulseWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Pulse.Accounts

  @doc "Account settings: add/update your email, and resend the confirmation link."
  def edit(conn, _params) do
    changeset = Accounts.change_user_email(conn.assigns.current_user)
    render(conn, :edit, form: to_form(changeset, as: "user"))
  end

  def update_email(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_email(user, user_params["current_password"], user_params) do
      {:ok, updated_user} ->
        # Best-effort — a mail-provider hiccup here shouldn't block
        # saving the address itself.
        Accounts.deliver_user_confirmation_instructions(updated_user, &url(~p"/users/confirm/#{&1}"))

        conn
        |> put_flash(:info, "Email saved — check your inbox to confirm it.")
        |> redirect(to: ~p"/users/settings")

      {:error, changeset} ->
        render(conn, :edit, form: to_form(changeset, as: "user"))
    end
  end

  def resend_confirmation(conn, _params) do
    case Accounts.deliver_user_confirmation_instructions(
           conn.assigns.current_user,
           &url(~p"/users/confirm/#{&1}")
         ) do
      {:ok, _email} ->
        put_flash(conn, :info, "Confirmation email sent.")

      {:error, :already_confirmed} ->
        put_flash(conn, :info, "That email is already confirmed.")

      {:error, :no_email} ->
        put_flash(conn, :error, "Add an email first.")
    end
    |> redirect(to: ~p"/users/settings")
  end
end
