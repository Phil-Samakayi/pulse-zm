defmodule Pulse.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  # Session tokens are valid this long; logging in again issues a fresh one
  # rather than extending the old one.
  @session_validity_in_days 60
  # Confirmation/reset-password tokens use a different (hashed-at-rest)
  # scheme than session tokens, since these ARE exposed outside the
  # server — emailed to the user, so they can end up in browser history,
  # a mail provider's logs, or a referrer header if the link is ever
  # clicked through from a webmail client. Only the hash is stored; the
  # raw token only ever exists in the emailed link itself.
  @hash_algorithm :sha256
  @confirm_validity_in_days 7
  @reset_password_validity_in_days 1
  @rand_size 32

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
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

  @doc """
  Builds an email-delivered token (context `"confirm"` or
  `"reset_password"`): a URL-safe encoded random token for the email
  link, paired with the schema struct holding the *hashed* version that
  actually gets stored. `sent_to` is pinned to the address it's being
  sent to right now, so the token stops working if that address changes
  before it's used.
  """
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %Pulse.Accounts.UserToken{
       token: hashed_token,
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  Query: the user for a given confirm/reset_password token, if it
  decodes, hasn't expired for its context, and the account's email
  still matches where the token was originally sent.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days

  def by_token_and_context_query(token, context) do
    from Pulse.Accounts.UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Every token of the given context(s) for a user — used to invalidate
  outstanding confirm/reset links when issuing a fresh one, and to log
  out every session on password reset.
  """
  def by_user_and_contexts_query(user, contexts) do
    from t in Pulse.Accounts.UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
