defmodule Pulse.Push do
  @moduledoc """
  Sends one Web Push notification to one browser — the delivery half of
  alerts (`Pulse.Alerts` decides who gets what).

  A browser that has allowed notifications gives Pulse a *subscription*:
  a push-service URL (`endpoint`, run by Google for Chrome, Mozilla for
  Firefox, …) plus two keys. Pulse encrypts the message with those keys,
  signs the request with its own VAPID key pair (configured in
  `config/runtime.exs`), and POSTs it to the endpoint; the push service
  wakes the phone, and the service worker (`priv/static/sw.js`) shows it.

  The actual sending is behind an adapter so tests never touch the
  network: `Pulse.Push.WebPush` in dev/prod, `Pulse.Push.TestAdapter` in
  test (`config :pulse, :push_adapter`).
  """

  @doc """
  Send `payload` (a JSON string) to `subscription` (the browser's
  subscription, also a JSON string). Returns `:ok`, `{:error, :expired}` when the
  browser has unsubscribed or the subscription is gone (delete it), or
  `{:error, reason}` for anything else.
  """
  @callback deliver(subscription :: String.t(), payload :: String.t(), opts :: keyword) ::
              :ok | {:error, :expired} | {:error, term}

  # How long a push service keeps trying a phone that's switched off or
  # offline before dropping the message. An alert that "power is back"
  # is still useful a few hours later, not a day later.
  @ttl_seconds 6 * 60 * 60

  @doc "Whether alerts are switched on — i.e. VAPID keys are configured."
  def enabled?, do: public_key() not in [nil, ""]

  @doc "The VAPID public key the browser needs to subscribe."
  def public_key, do: Application.get_env(:web_push_elixir, :vapid_public_key)

  @doc """
  Send `message` (a map with `:title`, `:body`, `:url` and `:tag`; see
  `priv/static/sw.js` for how each is used) to one subscription.
  """
  def deliver(subscription_json, %{} = message) do
    adapter().deliver(subscription_json, Jason.encode!(message), ttl: @ttl_seconds, urgency: :high)
  end

  defp adapter, do: Application.get_env(:pulse, :push_adapter, Pulse.Push.WebPush)
end

defmodule Pulse.Push.WebPush do
  @moduledoc "Sends for real, via the `web_push_elixir` library."
  @behaviour Pulse.Push

  require Logger

  @impl true
  def deliver(subscription, payload, opts) do
    case WebPushElixir.send_notification(subscription, payload, opts) do
      {:ok, _response} -> :ok
      {:error, :expired} -> {:error, :expired}
      {:error, reason} -> log_and_return(reason)
    end
  rescue
    # A malformed stored subscription makes the library raise while
    # decoding it; treat it like any other failed send.
    error -> log_and_return(error)
  end

  defp log_and_return(reason) do
    Logger.warning("Push notification failed: #{inspect(reason)}")
    {:error, reason}
  end
end
