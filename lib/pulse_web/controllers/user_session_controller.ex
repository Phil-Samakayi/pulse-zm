defmodule PulseWeb.UserSessionController do
  use PulseWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Pulse.Accounts
  alias PulseWeb.UserAuth

  @doc """
  Renders the login form. This is a plain controller-rendered page, not a
  LiveView — the form has no live validation or other behavior that needs
  a socket, so keeping it on plain HTTP means there's no persistent
  connection to drop and reconnect while someone is mid-keystroke. (A
  dropped/reconnecting LiveView socket forces a fresh mount, which replaces
  the DOM and resets the input to its default value — that's what was
  causing the login field to lose focus/clear after a few seconds.)
  """
  def new(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/")
    else
      form = to_form(%{"username" => nil}, as: "user")
      render(conn, :new, form: form)
    end
  end

  @doc """
  Handles the login form POST. This has to be a regular controller action,
  not a LiveView event — setting the session cookie requires writing an
  HTTP response header, which a LiveView socket push can't do.
  """
  def create(conn, %{"user" => user_params}) do
    %{"username" => username, "password" => password} = user_params

    if user = Accounts.get_user_by_username_and_password(username, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      conn
      |> put_flash(:error, "Invalid username or password")
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
