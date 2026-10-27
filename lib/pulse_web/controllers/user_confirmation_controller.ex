defmodule PulseWeb.UserConfirmationController do
  use PulseWeb, :controller

  alias Pulse.Accounts

  @doc """
  Confirms the email behind a `/users/confirm/:token` link. No login
  required — the link itself, not a session, is the proof of control.
  Always redirects, so there's no `UserConfirmationHTML` view module.
  """
  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email confirmed. You can now reset your password by email if you ever need to.")
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> put_flash(:error, "That confirmation link is invalid or has expired.")
        |> redirect(to: ~p"/")
    end
  end
end
