defmodule PulseWeb.LocationController do
  @moduledoc """
  Propose a new location for review. A plain controller page, not a
  LiveView, for the same reason as `PulseWeb.ReportController`: a normal
  form POST works whether or not the live connection is up, and nothing
  the user types can be wiped by a reconnecting socket.

  Requires login (`:require_login` in the router). Submissions always land
  with status "pending" and only become visible to everyone else once an
  admin approves them from the moderation queue
  (`PulseWeb.ModerationLive.Index`).

  Includes a honeypot field (`:website`, see `Pulse.Reports.Location`),
  hidden from real users with CSS. If it comes back filled in, the action
  pretends the submission succeeded (same flash, same redirect) without
  inserting anything, so a bot gets no sign it was caught.
  """

  use PulseWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Pulse.Reports
  alias Pulse.Reports.Location

  @submitted "Thanks — submitted for review. An admin will take a look soon."

  def new(conn, _params) do
    # Every location so far is in Lusaka, so start the city filled in.
    render_form(conn, Reports.change_location_submission(%Location{}, %{"city" => "Lusaka"}))
  end

  def create(conn, %{"location" => params}) do
    if honeypot_filled?(params) do
      conn |> put_flash(:info, @submitted) |> redirect(to: ~p"/")
    else
      attrs = Map.put(params, "submitted_by_id", conn.assigns.current_user.id)

      case Reports.submit_location(attrs) do
        {:ok, _location} ->
          conn |> put_flash(:info, @submitted) |> redirect(to: ~p"/")

        {:error, changeset} ->
          conn |> flash_base_error(changeset) |> render_form(changeset)
      end
    end
  end

  defp render_form(conn, changeset) do
    render(conn, :new, page_title: "Propose a location", form: to_form(changeset, as: "location"))
  end

  # The rate limit comes back as a :base error, which belongs to no single
  # field — show it as a flash.
  defp flash_base_error(conn, changeset) do
    case Keyword.get(changeset.errors, :base) do
      nil -> conn
      error -> put_flash(conn, :error, PulseWeb.CoreComponents.translate_error(error))
    end
  end

  defp honeypot_filled?(params), do: (params["website"] || "") != ""
end
