defmodule PulseWeb.ReportController do
  @moduledoc """
  Every way of writing a report: the one-tap outage buttons on the
  location page, the fuller outage form (with a note), the price form,
  and flagging a report as wrong.

  These are plain controller actions rather than LiveView events on
  purpose — see `PulseWeb.LocationLive.Show`'s moduledoc. A normal form
  POST works whether or not the page's live connection is up, so
  reporting keeps working on hosts where it isn't (Render's free plan).

  All routes are behind `:require_login`, and `load_location/2` only lets
  a request through for a location the current user is allowed to see —
  the same rule as the location page itself (`Reports.visible_to?/2`).
  """

  use PulseWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Pulse.Reports

  plug :load_location

  ## Outages

  def new_outage(conn, _params) do
    render_outage_form(conn, Reports.change_outage_report())
  end

  @doc """
  Handles both the one-tap buttons and the fuller form. The form sends
  `source=form`, so a validation error re-renders it with the errors and
  what was typed; a one-tap button has nothing to re-render, so an error
  (in practice the duplicate-report cooldown or the rate limit) goes
  back to the location page as a flash instead.
  """
  def create_outage(conn, %{"outage_report" => params} = all_params) do
    location = conn.assigns.location
    thanks = "Thanks — your report is in."

    if honeypot_filled?(params) do
      thank_and_return(conn, thanks)
    else
      attrs =
        params
        |> Map.put("location_id", location.id)
        |> Map.put("reported_by_id", conn.assigns.current_user.id)

      case Reports.create_outage_report(attrs) do
        {:ok, _report} ->
          thank_and_return(conn, thanks)

        {:error, changeset} ->
          if all_params["source"] == "form" do
            conn |> flash_base_error(changeset) |> render_outage_form(changeset)
          else
            conn
            |> put_flash(:error, error_summary(changeset))
            |> redirect(to: ~p"/locations/#{location.id}")
          end
      end
    end
  end

  ## Prices

  def new_price(conn, _params) do
    render_price_form(conn, Reports.change_price_report())
  end

  def create_price(conn, %{"price_report" => params}) do
    location = conn.assigns.location
    thanks = "Thanks — your price report is in."

    if honeypot_filled?(params) do
      thank_and_return(conn, thanks)
    else
      attrs =
        params
        |> Map.put("location_id", location.id)
        |> Map.put("reported_by_id", conn.assigns.current_user.id)

      case Reports.create_price_report(attrs) do
        {:ok, _report} ->
          thank_and_return(conn, thanks)

        {:error, changeset} ->
          conn |> flash_base_error(changeset) |> render_price_form(changeset)
      end
    end
  end

  ## Flags

  def new_flag(conn, %{"type" => type, "report_id" => report_id}) do
    with_report(conn, type, report_id, fn conn, report ->
      render(conn, :new_flag,
        page_title: "Flag a report · #{conn.assigns.location.name}",
        type: type,
        report: report,
        form: to_form(%{"reason" => ""}, as: "flag")
      )
    end)
  end

  def create_flag(conn, %{"type" => type, "report_id" => report_id} = params) do
    reason = get_in(params, ["flag", "reason"]) || ""

    with_report(conn, type, report_id, fn conn, report ->
      result =
        case type do
          "outage" -> Reports.flag_outage_report(report, %{"flag_reason" => reason})
          "price" -> Reports.flag_price_report(report, %{"flag_reason" => reason})
        end

      case result do
        {:ok, _report} ->
          thank_and_return(conn, "Thanks — flagged for review.")

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Couldn't flag that report — keep the reason under 280 characters.")
          |> redirect(to: ~p"/locations/#{conn.assigns.location.id}")
      end
    end)
  end

  ## Helpers

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

  # Only a report that belongs to *this* location can be flagged from
  # this location's URL.
  defp with_report(conn, type, report_id, fun) do
    location = conn.assigns.location

    report =
      with {id, ""} <- Integer.parse(report_id),
           %{} = report <- fetch_report(type, id),
           true <- report.location_id == location.id do
        report
      else
        _ -> nil
      end

    if report do
      fun.(conn, report)
    else
      conn
      |> put_flash(:error, "That report couldn't be found.")
      |> redirect(to: ~p"/locations/#{location.id}")
    end
  end

  defp fetch_report("outage", id), do: Reports.get_outage_report(id)
  defp fetch_report("price", id), do: Reports.get_price_report(id)
  defp fetch_report(_type, _id), do: nil

  defp render_outage_form(conn, changeset) do
    render(conn, :new_outage,
      page_title: "Report power or water · #{conn.assigns.location.name}",
      form: to_form(changeset, as: "outage_report")
    )
  end

  defp render_price_form(conn, changeset) do
    render(conn, :new_price,
      page_title: "Report a price · #{conn.assigns.location.name}",
      form: to_form(changeset, as: "price_report")
    )
  end

  defp thank_and_return(conn, message) do
    conn
    |> put_flash(:info, message)
    |> redirect(to: ~p"/locations/#{conn.assigns.location.id}")
  end

  # The duplicate-report cooldown and the rate limit come back as a
  # :base error, which belongs to no single field — show it as a flash.
  defp flash_base_error(conn, changeset) do
    case Keyword.get(changeset.errors, :base) do
      nil -> conn
      error -> put_flash(conn, :error, PulseWeb.CoreComponents.translate_error(error))
    end
  end

  defp error_summary(changeset) do
    case Keyword.get(changeset.errors, :base) do
      nil -> "Couldn't save that report. Please try again."
      error -> PulseWeb.CoreComponents.translate_error(error)
    end
  end

  defp honeypot_filled?(params), do: (params["website"] || "") != ""
end
