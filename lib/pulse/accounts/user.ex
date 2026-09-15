defmodule Pulse.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :is_admin, :boolean, default: false

    has_many :outage_reports, Pulse.Reports.OutageReport, foreign_key: :reported_by_id
    has_many :price_reports, Pulse.Reports.PriceReport, foreign_key: :reported_by_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Registration changeset: validates the username, then hashes the password
  and drops the plaintext from the changeset. Pass `hash_password: false`
  (used for the live-validating registration form) to skip the actual
  hashing while still running every other validation — hashing on every
  keystroke would be wasted CPU.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :password])
    |> validate_username()
    |> validate_password(opts)
  end

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 40)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
      message: "may only contain letters, numbers, and underscores"
    )
    |> unsafe_validate_unique(:username, Pulse.Repo)
    |> unique_constraint(:username)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 128)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Pbkdf2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Verifies a password against the stored hash (PBKDF2-HMAC-SHA512, via
  Erlang's built-in `:crypto` — no C compiler needed to build this
  dependency, unlike Bcrypt, which is why this project uses it instead;
  it's the same family of algorithm Django defaults to). Always runs a
  dummy check even when there's no matching user, so a login attempt for a
  username that doesn't exist takes the same time as a wrong password for
  one that does — otherwise response timing alone reveals which usernames
  are registered.
  """
  def valid_password?(%Pulse.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Pbkdf2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Pbkdf2.no_user_verify()
    false
  end
end
