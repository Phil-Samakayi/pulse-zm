defmodule Pulse.AccountsTest do
  use Pulse.DataCase, async: true

  alias Pulse.Accounts
  alias Pulse.Accounts.User

  import Pulse.AccountsFixtures

  describe "register_user/1" do
    test "registers a user with a hashed (not plaintext) password" do
      {:ok, user} = Accounts.register_user(valid_user_attrs(username: "newperson"))

      assert user.username == "newperson"
      assert is_binary(user.hashed_password)
      assert user.hashed_password != valid_user_password()
    end

    test "requires username and password" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{username: ["can't be blank"], password: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates username format" do
      {:error, changeset} = Accounts.register_user(valid_user_attrs(username: "has spaces"))

      assert "may only contain letters, numbers, and underscores" in errors_on(changeset).username
    end

    test "validates username length" do
      {:error, changeset} = Accounts.register_user(valid_user_attrs(username: "ab"))

      assert "should be at least 3 character(s)" in errors_on(changeset).username
    end

    test "validates password length" do
      {:error, changeset} = Accounts.register_user(valid_user_attrs(password: "short"))

      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end

    test "enforces unique usernames" do
      %{username: username} = user_fixture()

      {:error, changeset} = Accounts.register_user(valid_user_attrs(username: username))

      assert "has already been taken" in errors_on(changeset).username
    end

    test "requires an email" do
      {:error, changeset} = Accounts.register_user(valid_user_attrs(email: nil))

      assert "can't be blank" in errors_on(changeset).email
    end

    test "validates email format" do
      {:error, changeset} = Accounts.register_user(valid_user_attrs(email: "not-an-email"))

      assert "must look like an email address" in errors_on(changeset).email
    end

    test "downcases the email" do
      {:ok, user} = Accounts.register_user(valid_user_attrs(email: "Mixed.Case@Example.com"))

      assert user.email == "mixed.case@example.com"
    end

    test "enforces unique emails, case-insensitively" do
      %{email: email} = user_fixture()

      {:error, changeset} = Accounts.register_user(valid_user_attrs(email: String.upcase(email)))

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset without hashing the password (for live validation)" do
      changeset = Accounts.change_user_registration(%User{}, valid_user_attrs())

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :hashed_password) == nil
    end
  end

  describe "get_user_by_username/1" do
    test "returns the user with the given username" do
      user = user_fixture()

      assert %{id: id} = Accounts.get_user_by_username(user.username)
      assert id == user.id
    end

    test "returns nil for an unknown username" do
      assert Accounts.get_user_by_username("nobody") == nil
    end
  end

  describe "get_user_by_username_and_password/2" do
    test "returns the user on a correct password" do
      user = user_fixture()

      assert %{id: id} = Accounts.get_user_by_username_and_password(user.username, valid_user_password())
      assert id == user.id
    end

    test "returns nil on a wrong password" do
      user = user_fixture()

      refute Accounts.get_user_by_username_and_password(user.username, "wrong password")
    end

    test "returns nil for an unknown username" do
      refute Accounts.get_user_by_username_and_password("nobody", "whatever123")
    end
  end

  describe "session tokens" do
    test "generate_user_session_token/1 creates a token that resolves back to the user" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert %{id: id} = Accounts.get_user_by_session_token(token)
      assert id == user.id
    end

    test "delete_user_session_token/1 invalidates the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      Accounts.delete_user_session_token(token)

      refute Accounts.get_user_by_session_token(token)
    end

    test "get_user_by_session_token/1 returns nil for a bogus token" do
      refute Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32))
    end
  end

  describe "change_user_email/2" do
    test "returns an email changeset" do
      user = user_fixture()
      changeset = Accounts.change_user_email(user, %{email: "new@example.com"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :email) == "new@example.com"
    end
  end

  describe "update_user_email/3" do
    test "sets the email on an account that had none yet" do
      user = legacy_user_fixture()
      refute user.email

      {:ok, updated} = Accounts.update_user_email(user, valid_user_password(), %{"email" => "added@example.com"})

      assert updated.email == "added@example.com"
    end

    test "resets confirmed_at when the email actually changes" do
      user = confirmed_user_fixture()
      assert user.confirmed_at

      {:ok, updated} = Accounts.update_user_email(user, valid_user_password(), %{"email" => unique_user_email()})

      refute updated.confirmed_at
    end

    test "leaves confirmed_at alone when the email is unchanged" do
      user = confirmed_user_fixture()

      {:ok, updated} = Accounts.update_user_email(user, valid_user_password(), %{"email" => user.email})

      assert updated.confirmed_at
    end

    test "rejects an email already used by another account" do
      %{email: taken} = user_fixture()
      user = user_fixture()

      {:error, changeset} = Accounts.update_user_email(user, valid_user_password(), %{"email" => taken})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "refuses to change the email without the right current password" do
      user = confirmed_user_fixture()

      {:error, changeset} =
        Accounts.update_user_email(user, "not the password", %{"email" => unique_user_email()})

      assert "is not valid" in errors_on(changeset).current_password
      assert Accounts.get_user!(user.id).email == user.email
    end

    test "also requires the password when adding a first email" do
      user = legacy_user_fixture()

      assert {:error, changeset} =
               Accounts.update_user_email(user, nil, %{"email" => "added@example.com"})

      assert "is not valid" in errors_on(changeset).current_password
      refute Accounts.get_user!(user.id).email
    end
  end

  describe "deliver_user_confirmation_instructions/2 and confirm_user/1" do
    test "confirms the user when the token is valid" do
      user = user_fixture()
      refute User.confirmed?(user)

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_confirmation_instructions(user, url_fun)
        end)

      assert {:ok, confirmed} = Accounts.confirm_user(token)
      assert confirmed.confirmed_at
    end

    test "a confirmation token can't be reused" do
      user = user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_confirmation_instructions(user, url_fun)
        end)

      assert {:ok, _} = Accounts.confirm_user(token)
      assert :error = Accounts.confirm_user(token)
    end

    test "rejects a bogus token" do
      assert :error = Accounts.confirm_user("not-a-real-token")
    end

    test "won't send to an account with no email" do
      user = legacy_user_fixture()

      assert {:error, :no_email} =
               Accounts.deliver_user_confirmation_instructions(user, &"#{&1}")
    end

    test "won't send to an already-confirmed account" do
      user = confirmed_user_fixture()

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(user, &"#{&1}")
    end

    test "issuing a fresh confirmation link invalidates the previous one" do
      user = user_fixture()

      old_token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_confirmation_instructions(user, url_fun)
        end)

      {:ok, _email} = Accounts.deliver_user_confirmation_instructions(user, &"#{&1}")

      assert :error = Accounts.confirm_user(old_token)
    end
  end

  describe "deliver_user_reset_password_instructions/2 and get_user_by_reset_password_token/1" do
    test "won't send to an account with no email" do
      user = legacy_user_fixture()

      assert {:error, :no_email} =
               Accounts.deliver_user_reset_password_instructions(user, &"#{&1}")
    end

    test "won't send to an unconfirmed account" do
      user = user_fixture()
      refute User.confirmed?(user)

      assert {:error, :unconfirmed} =
               Accounts.deliver_user_reset_password_instructions(user, &"#{&1}")
    end

    test "a valid token for a confirmed account resolves back to that user" do
      user = confirmed_user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_reset_password_instructions(user, url_fun)
        end)

      assert %{id: id} = Accounts.get_user_by_reset_password_token(token)
      assert id == user.id
    end

    test "returns nil for a bogus token" do
      refute Accounts.get_user_by_reset_password_token("not-a-real-token")
    end

    test "a confirm token doesn't work as a reset-password token" do
      user = confirmed_user_fixture()

      # Built directly (bypassing the "already confirmed" guard on
      # deliver_user_confirmation_instructions/2) purely to get a
      # same-shaped token of the *wrong* context, to test that
      # get_user_by_reset_password_token/1 checks context and not just
      # "does a token with this hash exist".
      {confirm_token, user_token} = Pulse.Accounts.UserToken.build_email_token(user, "confirm")
      Pulse.Repo.insert!(user_token)

      refute Accounts.get_user_by_reset_password_token(confirm_token)
    end
  end

  describe "change_user_password/2 and reset_user_password/2" do
    test "resets the password and logs out every existing session" do
      user = confirmed_user_fixture()
      session_token = Accounts.generate_user_session_token(user)

      assert {:ok, updated} = Accounts.reset_user_password(user, %{"password" => "a-new-password"})

      assert Accounts.get_user_by_username_and_password(user.username, "a-new-password")
      refute Accounts.get_user_by_session_token(session_token)
      assert updated.hashed_password != user.hashed_password
    end

    test "rejects a too-short password" do
      user = confirmed_user_fixture()

      assert {:error, changeset} = Accounts.reset_user_password(user, %{"password" => "short"})
      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end
  end
end
