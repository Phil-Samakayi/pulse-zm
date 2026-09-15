defmodule Pulse.Accounts do
  @moduledoc """
  User registration and session management.

  This is a hand-written equivalent of what `mix phx.gen.auth` would
  normally generate. That generator couldn't be run for this project — see
  the README for why — so this context, its schemas, and the plugs in
  `PulseWeb.UserAuth` were written to match its standard shape, trimmed to
  what Pulse actually needs (no email confirmation or password-reset-by-
  email flow, since there's no mailer set up — this mirrors the original
  Django version's plain username/password accounts).
  """

  import Ecto.Query, warn: false
  alias Pulse.Repo
  alias Pulse.Accounts.{User, UserToken}

  ## Users

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc "Returns the user if the username/password combination is valid, else nil."
  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = get_user_by_username(username)
    if User.valid_password?(user, password), do: user
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "A changeset for tracking registration-form changes, without hashing on every keystroke."
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Session

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Looks up the user for a session token, if the token exists and hasn't expired."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
