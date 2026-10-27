defmodule Pulse.AccountsFixtures do
  @moduledoc """
  Helpers for creating `Pulse.Accounts` entities in tests. Mirrors the
  fixture modules `mix phx.gen.auth` would normally generate — see
  `Pulse.Accounts`'s moduledoc for why this project's auth is
  hand-written instead.
  """

  alias Pulse.Accounts

  def unique_username, do: "user#{System.unique_integer([:positive])}"
  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      username: unique_username(),
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attrs()
      |> Accounts.register_user()

    user
  end

  @doc "A user with `is_admin: true` — gates `PulseWeb.ModerationLive.Index`."
  def admin_fixture(attrs \\ %{}) do
    attrs
    |> user_fixture()
    |> Ecto.Changeset.change(is_admin: true)
    |> Pulse.Repo.update!()
  end

  @doc "A user whose email is confirmed — can use password reset."
  def confirmed_user_fixture(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs
    |> user_fixture()
    |> Ecto.Changeset.change(confirmed_at: now)
    |> Pulse.Repo.update!()
  end

  @doc """
  A user as if they predate the email feature (or skipped adding one):
  registered with no email at all, the way the pre-existing seeded
  demo accounts are. Real registration requires an email now (see
  `Pulse.Accounts.User.registration_changeset/3`), so this bypasses
  that changeset entirely rather than going through
  `Pulse.Accounts.register_user/1` — the whole point is to simulate an
  account that path could no longer produce.
  """
  def legacy_user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{username: unique_username(), password: valid_user_password()})

    %Pulse.Accounts.User{}
    |> Ecto.Changeset.change(
      username: attrs.username,
      hashed_password: Pbkdf2.hash_pwd_salt(attrs.password)
    )
    |> Pulse.Repo.insert!()
  end

  @doc """
  Captures the raw token embedded in a confirmation/reset-password
  email without needing a real mailbox: pass a 1-arg function that
  calls the `Pulse.Accounts` deliver function with the `url_fun` it's
  given, e.g.:

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_confirmation_instructions(user, url_fun)
        end)

  This wraps the token in recognizable markers instead of a real URL,
  then pulls it back out of the email body Pulse.Accounts.UserNotifier
  actually sent (via the Local mailer in test).
  """
  def extract_user_token(generate_email_fun) do
    {:ok, captured_email} = generate_email_fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
