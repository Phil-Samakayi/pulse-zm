defmodule Pulse.Push.TestAdapter do
  @moduledoc """
  The test-only push sender (`config :pulse, :push_adapter` in
  config/test.exs): instead of contacting a push service, it sends
  `{:push, endpoint, message}` to the calling process, so a test can
  `assert_received` it. Alerts are sent inline in test
  (`config :pulse, :alerts_inline`), so the caller is the test itself.

  An endpoint containing "expired" behaves like a browser that has
  unsubscribed (`{:error, :expired}`), to test that such subscriptions
  get cleaned up.
  """
  @behaviour Pulse.Push

  @impl true
  def deliver(subscription, payload, _opts) do
    %{"endpoint" => endpoint} = Jason.decode!(subscription)

    if String.contains?(endpoint, "expired") do
      {:error, :expired}
    else
      send(self(), {:push, endpoint, Jason.decode!(payload)})
      :ok
    end
  end
end
