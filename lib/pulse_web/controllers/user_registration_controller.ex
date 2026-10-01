defmodule PulseWeb.UserRegistrationController do
  use PulseWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Pulse.Accounts
  alias Pulse.Accounts.User

  @doc """
  Renders the registration form. Plain controller-rendered page — same
  reasoning as UserSessionController.new/2: this form doesn't need a
  socket to function, and keeping one open is what caused the exact
  focus-loss bug fixed there (a dropped/reconnected LiveView socket
  remounts from scratch and wipes out whatever had already been typed).
  Losing live, as-you-type validation is the trade-off; errors now show
  after submitting instead of after each keystroke.
  """
  def new(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/")
    else
      changeset = Accounts.change_user_registration(%User{})
      render(conn, :new, form: to_form(changeset, as: "user"), check_errors: false)
    end
  end

  @doc "Handles the registration form POST."
  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Account created — please log in.")
        |> redirect(to: ~p"/users/log_in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, form: to_form(changeset, as: "user"), check_errors: true)
    end
  end
end
