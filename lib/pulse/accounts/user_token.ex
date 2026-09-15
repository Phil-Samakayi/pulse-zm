defmodule Pulse.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  # Session tokens are valid this long; logging in again issues a fresh one
  # rather than extending the old one.
  @session_validity_in_days 60
  @rand_size 32

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :user, Pulse.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a random, high-entropy session token. Unlike a password-reset
  token (sent over email, so hashed before storage as defense in depth),
  a session token never leaves the server except inside the client's own
  encrypted session cookie, so storing it as-is is standard practice here.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %Pulse.Accounts.UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc "Query: the user for a given session token, if it exists and hasn't expired."
  def verify_session_token_query(token) do
    query =
      from t in by_token_and_context_query(token, "session"),
        join: user in assoc(t, :user),
        where: t.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  def by_token_and_context_query(token, context) do
    from Pulse.Accounts.UserToken, where: [token: ^token, context: ^context]
  end
end
