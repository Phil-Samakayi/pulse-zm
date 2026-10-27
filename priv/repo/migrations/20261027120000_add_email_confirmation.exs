defmodule Pulse.Repo.Migrations.AddEmailConfirmationToUsersAndTokens do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Nullable: accounts that existed before this feature (the seeded
      # demo users, any real signups so far) keep working with no email
      # until they add one from account settings. New registrations
      # require one going forward (enforced in Pulse.Accounts.User's
      # registration changeset, not here).
      add :email, :string
      add :confirmed_at, :utc_datetime
    end

    # Partial: many rows can have a null email (grandfathered accounts),
    # but no two accounts can share the same real one.
    create unique_index(:users, [:email], where: "email IS NOT NULL")

    alter table(:users_tokens) do
      # Only set on email-delivered tokens (confirm / reset_password) —
      # pins the token to the address it was sent to, so it stops
      # working if that address changes before it's used. Unused for
      # "session" tokens.
      add :sent_to, :string
    end
  end
end
