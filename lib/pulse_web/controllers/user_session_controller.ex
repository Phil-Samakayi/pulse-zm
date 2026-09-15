defmodule PulseWeb.UserSessionController do
  use PulseWeb, :controller

  alias Pulse.Accounts
  alias PulseWeb.UserAuth

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
