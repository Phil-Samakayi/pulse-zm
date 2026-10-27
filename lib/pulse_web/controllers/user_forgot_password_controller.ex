defmodule PulseWeb.UserForgotPasswordController do
  use PulseWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Pulse.Accounts

  @doc "Renders the 'reset my password' request form."
  def new(conn, _params) do
    render(conn, :new, form: to_form(%{"email" => nil}, as: "user"))
  end

  @doc """
  Always shows the same flash regardless of whether the email matches
  an account, is confirmed, or exists at all — so this form can't be
  used to probe which emails are registered.
  """
  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
    end

    conn
    |> put_flash(
      :info,
      "If that's a confirmed email on a Pulse account, we've sent reset instructions to it."
    )
    |> redirect(to: ~p"/users/log_in")
  end
end
