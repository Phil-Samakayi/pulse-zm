defmodule PulseWeb.AlertController do
  @moduledoc """
  Following and unfollowing a location ("Get alerts" / "Turn off" on the
  location page). Tap-only form POSTs, like the report buttons, so they
  work without the page's live connection — see
  `PulseWeb.LocationLive.Show`'s moduledoc.

  The browser's push subscription is saved separately, by
  `PulseWeb.PushSubscriptionController`, before the "Get alerts" form is
  submitted. Same location rule as reporting: only places the user can
  see (`Reports.visible_to?/2`).
  """

  use PulseWeb, :controller

  alias Pulse.{Alerts, Reports}

  plug :load_location

  def follow_location(conn, _params) do
    location = conn.assigns.location

    case Alerts.follow_location(conn.assigns.current_user, location) do
      {:ok, _alert} ->
        conn
        |> put_flash(
          :info,
          "Alerts on for #{location.name}. We'll tell you when power or water changes there."
        )
        |> redirect(to: ~p"/locations/#{location.id}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Couldn't turn on alerts just now. Please try again.")
        |> redirect(to: ~p"/locations/#{location.id}")
    end
  end

  def unfollow_location(conn, _params) do
    location = conn.assigns.location
    :ok = Alerts.unfollow_location(conn.assigns.current_user, location)

    conn
    |> put_flash(:info, "Alerts off for #{location.name}.")
    |> redirect(to: ~p"/locations/#{location.id}")
  end

  defp load_location(conn, _opts) do
    user = conn.assigns.current_user

    with {id, ""} <- Integer.parse(conn.params["location_id"] || ""),
         %{} = location <- Reports.get_location(id),
         true <- Reports.visible_to?(location, user) do
      assign(conn, :location, location)
    else
      _ ->
        conn
        |> put_flash(:error, "That location isn't available.")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end
end
