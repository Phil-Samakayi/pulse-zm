defmodule PulseWeb.ModerationController do
  @moduledoc """
  Admin-only moderation queue: pending location submissions to approve
  or reject, and flagged outage/price reports to clear once reviewed.

  A plain controller page rather than a LiveView, like the report and
  propose-a-location pages (see `PulseWeb.LocationLive.Show`'s moduledoc):
  every action is a normal form POST that redirects back here, so the
  queue works whether or not a live connection can stay up. Nothing here
  needs live updates — it's one admin working through a list.

  Gated by `:require_login` and then `:admins_only` (`UserAuth.require_admin/2`)
  in the router.
  """

  use PulseWeb, :controller

  alias Pulse.Reports
  alias Pulse.Reports.Location

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Moderation",
      pending_locations: Reports.list_pending_locations(),
      flagged: Reports.list_flagged_reports()
    )
  end

  def approve(conn, %{"id" => id}) do
    with_pending_location(conn, id, fn conn, location ->
      case Reports.approve_location(location) do
        {:ok, _} -> back_to_queue(conn, :info, "#{location.name} approved — now visible to everyone.")
        {:error, _} -> back_to_queue(conn, :error, "Couldn't approve that location.")
      end
    end)
  end

  def new_reject(conn, %{"id" => id}) do
    with_pending_location(conn, id, fn conn, location ->
      render_reject_form(conn, location, "", [])
    end)
  end

  def reject(conn, %{"id" => id} = params) do
    reason = String.trim(get_in(params, ["reject", "reason"]) || "")

    with_pending_location(conn, id, fn conn, location ->
      case Reports.reject_location(location, reason) do
        {:ok, _} ->
          back_to_queue(conn, :info, "#{location.name} rejected.")

        {:error, changeset} ->
          errors =
            changeset.errors
            |> Keyword.get_values(:rejection_note)
            |> Enum.map(&PulseWeb.CoreComponents.translate_error/1)

          render_reject_form(conn, location, reason, errors)
      end
    end)
  end

  def clear_flag(conn, %{"type" => type, "id" => id}) do
    report =
      case {type, Integer.parse(id)} do
        {"outage", {id, ""}} -> Reports.get_outage_report(id)
        {"price", {id, ""}} -> Reports.get_price_report(id)
        _ -> nil
      end

    result =
      case {type, report} do
        {_, nil} -> :not_found
        {_, %{is_flagged: false}} -> :not_found
        {"outage", report} -> Reports.clear_outage_flag(report)
        {"price", report} -> Reports.clear_price_flag(report)
      end

    case result do
      {:ok, _} -> back_to_queue(conn, :info, "Flag cleared.")
      :not_found -> back_to_queue(conn, :error, "That report is no longer in the queue.")
      {:error, _} -> back_to_queue(conn, :error, "Couldn't clear that flag.")
    end
  end

  ## Helpers

  defp with_pending_location(conn, id, fun) do
    pending = Location.pending()

    with {id, ""} <- Integer.parse(id),
         %Location{status: ^pending} = location <- Reports.get_location(id) do
      fun.(conn, location)
    else
      _ -> back_to_queue(conn, :error, "That submission is no longer in the queue.")
    end
  end

  defp render_reject_form(conn, location, reason, errors) do
    render(conn, :reject,
      page_title: "Reject #{location.name}",
      location: location,
      reason: reason,
      errors: errors
    )
  end

  defp back_to_queue(conn, kind, message) do
    conn |> put_flash(kind, message) |> redirect(to: ~p"/moderation")
  end
end
