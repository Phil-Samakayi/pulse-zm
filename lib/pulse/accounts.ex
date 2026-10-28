defmodule Pulse.Accounts do
  @moduledoc """
  User registration, session management, email confirmation, and
  password reset.

  This is a hand-written equivalent of what `mix phx.gen.auth` would
  normally generate. That generator couldn't be run for this project —
  see the README for why — so this context, its schemas, and the plugs
  in `PulseWeb.UserAuth` were written to match its standard shape, and
  later extended back closer to the full shape as Pulse grew password
  reset and email confirmation (see `Pulse.Accounts.UserNotifier` for
  how those emails actually get sent).

  Confirmation is "soft": an account works fully right after
  registration. Confirming the on-file email only unlocks
  password-reset-by-email — you can't reset a password to an address
  nobody's proven they control. Accounts that predate this feature (or
  that skipped adding an email) simply can't use password reset until
  they add and confirm one via the account settings page.
  """

  import Ecto.Query, warn: false
  alias Pulse.Repo
  alias Pulse.Accounts.{User, UserToken, UserNotifier}

  ## Users

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
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

  ## Email / confirmation

  @doc "For the 'add/update your email' settings form."
  def change_user_email(%User{} = user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
  end

  @doc """
  Sets (or changes) a user's email, but only if `current_password` is
  right — see `User.validate_current_password/2` for why. If the address
  actually changes, resets `confirmed_at` so the new address has to be
  (re)confirmed before it can be used for password reset — a
  confirmation on the old address shouldn't silently carry over to a
  new one.
  """
  def update_user_email(%User{} = user, current_password, attrs) do
    changeset =
      user
      |> User.email_changeset(attrs)
      |> User.validate_current_password(current_password)

    changeset =
      if Ecto.Changeset.get_change(changeset, :email) do
        Ecto.Changeset.put_change(changeset, :confirmed_at, nil)
      else
        changeset
      end

    Repo.update(changeset)
  end

  @doc """
  Sends a confirmation email, unless the account has no email on file
  or is already confirmed. `confirmation_url_fun` builds the link from
  the url-safe token — kept out of this context so it doesn't need to
  know about routes. Any outstanding confirm link is invalidated first,
  so at most one stays valid at a time.
  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    cond do
      is_nil(user.email) ->
        {:error, :no_email}

      User.confirmed?(user) ->
        {:error, :already_confirmed}

      true ->
        Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["confirm"]))
        {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
        Repo.insert!(user_token)
        UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc "Confirms a user from the token in their confirmation email."
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query) do
      confirm_user_and_clear_tokens(user)
    else
      _ -> :error
    end
  end

  defp confirm_user_and_clear_tokens(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, Ecto.Changeset.change(user, confirmed_at: now))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _step, _reason, _changes} -> :error
    end
  end

  ## Password reset

  @doc """
  Sends password-reset instructions, unless the account has no email on
  file or that email isn't confirmed yet. Any outstanding reset link is
  invalidated first, so at most one stays valid at a time.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    cond do
      is_nil(user.email) ->
        {:error, :no_email}

      not User.confirmed?(user) ->
        {:error, :unconfirmed}

      true ->
        Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
        {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
        Repo.insert!(user_token)
        UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
    end
  end

  @doc "The user for a given reset-password token, if it's valid and hasn't expired — else nil."
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc "A changeset for the 'set a new password' form, before submitting."
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Resets the password and, as a safety measure, logs the account out
  everywhere by deleting every existing session token — if someone else
  had this account open (plausibly the reason a reset was needed), this
  signs them out too.
  """
  def reset_user_password(%User{} = user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["session"]))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes} -> {:error, changeset}
    end
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
