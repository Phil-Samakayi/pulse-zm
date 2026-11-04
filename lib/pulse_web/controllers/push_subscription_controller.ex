defmodule PulseWeb.PushSubscriptionController do
  @moduledoc """
  Saves the push subscription a browser hands over once its user allows
  notifications. Called with `fetch` from `assets/js/app.js` (the JSON
  from `pushManager.subscribe()`), just before a "Get alerts" form is
  submitted, so it answers in JSON rather than redirecting.
  """

  use PulseWeb, :controller

  alias Pulse.Alerts

  def create(conn, params) do
    case Alerts.save_subscription(conn.assigns.current_user, params) do
      {:ok, _subscription} ->
        json(conn, %{ok: true})

      {:error, _reason} ->
        conn
        |> put_status(422)
        |> json(%{ok: false})
    end
  end
end
