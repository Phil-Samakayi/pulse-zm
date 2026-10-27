defmodule PulseWeb.ModerationLive.Index do
  @moduledoc """
  Admin-only moderation queue: pending location submissions awaiting
  approve/reject, plus every flagged outage/price report with a button
  to clear the flag once it's been reviewed. Gated by the `:ensure_admin`
  on_mount hook — see `PulseWeb.UserAuth` and the router.
  """

  use PulseWeb, :live_view

  alias Pulse.Reports
  alias Pulse.Reports.PriceReport

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl">
      <.header>
        Moderation queue
        <:subtitle>Pending location submissions, and reports the community has flagged.</:subtitle>
      </.header>

      <section class="mt-8">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          Pending locations ({length(@pending_locations)})
        </h2>

        <p :if={@pending_locations == []} class="mt-2 text-sm text-ink-soft">Nothing pending.</p>

        <ul
          :if={@pending_locations != []}
          class="mt-2 divide-y divide-line rounded-lg border border-line"
        >
          <li :for={location <- @pending_locations} class="px-4 py-3">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="font-medium">
                  {location.name}
                  <span class="font-normal text-ink-soft">
                    ({location.city} · {group_label(location.location_type)})
                  </span>
                </p>
                <p class="mt-1 text-xs text-ink-soft">Proposed by {submitter_name(location)}</p>
              </div>

              <div :if={@rejecting != location.id} class="flex shrink-0 gap-3">
                <button
                  type="button"
                  phx-click="approve_location"
                  phx-value-id={location.id}
                  class="text-sm font-semibold text-teal hover:underline"
                >
                  Approve
                </button>
                <button
                  type="button"
                  phx-click="start_reject"
                  phx-value-id={location.id}
                  class="text-sm font-semibold text-danger hover:underline"
                >
                  Reject
                </button>
              </div>
            </div>

            <form
              :if={@rejecting == location.id}
              phx-submit="submit_reject"
              class="mt-3 flex items-center gap-2"
            >
              <input type="hidden" name="location_id" value={location.id} />
              <input
                type="text"
                name="reason"
                placeholder="Why is this being rejected?"
                required
                class="flex-1 rounded-md border-line text-sm focus:border-teal focus:ring-0"
              />
              <button type="submit" class="text-xs font-semibold text-danger hover:underline">
                Confirm reject
              </button>
              <button
                type="button"
                phx-click="cancel_reject"
                class="text-xs text-ink-soft hover:underline"
              >
                Cancel
              </button>
            </form>
          </li>
        </ul>
      </section>

      <section class="mt-10">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          Outage reports ({length(@flagged.outages)})
        </h2>

        <p :if={@flagged.outages == []} class="mt-2 text-sm text-ink-soft">Nothing flagged.</p>

        <.table :if={@flagged.outages != []} id="flagged-outages" rows={@flagged.outages}>
          <:col :let={r} label="Location">{r.location.name}</:col>
          <:col :let={r} label="Report">{r.utility} — {r.status}</:col>
          <:col :let={r} label="Reported by">{reporter_name(r)}</:col>
          <:col :let={r} label="Flag reason">{blank_dash(r.flag_reason)}</:col>
          <:action :let={r}>
            <button
              type="button"
              phx-click="clear_outage"
              phx-value-id={r.id}
              class="text-sm font-semibold text-ink hover:text-copper-strong hover:underline"
            >
              Clear flag
            </button>
          </:action>
        </.table>
      </section>

      <section class="mt-10">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          Price reports ({length(@flagged.prices)})
        </h2>

        <p :if={@flagged.prices == []} class="mt-2 text-sm text-ink-soft">Nothing flagged.</p>

        <.table :if={@flagged.prices != []} id="flagged-prices" rows={@flagged.prices}>
          <:col :let={r} label="Location">{r.location.name}</:col>
          <:col :let={r} label="Report">
            {commodity_summary(r)}: K{Decimal.to_string(r.price_kwacha)} / {r.unit}
          </:col>
          <:col :let={r} label="Reported by">{reporter_name(r)}</:col>
          <:col :let={r} label="Flag reason">{blank_dash(r.flag_reason)}</:col>
          <:action :let={r}>
            <button
              type="button"
              phx-click="clear_price"
              phx-value-id={r.id}
              class="text-sm font-semibold text-ink hover:text-copper-strong hover:underline"
            >
              Clear flag
            </button>
          </:action>
        </.table>
      </section>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       pending_locations: Reports.list_pending_locations(),
       rejecting: nil,
       flagged: Reports.list_flagged_reports(),
       page_title: "Moderation"
     )}
  end

  def handle_event("approve_location", %{"id" => id}, socket) do
    case find_location(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That submission is no longer in the queue.")}

      location ->
        case Reports.approve_location(location) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "#{location.name} approved — now visible to everyone.")
             |> refresh_pending()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Couldn't approve that location.")}
        end
    end
  end

  def handle_event("start_reject", %{"id" => id}, socket) do
    {:noreply, assign(socket, rejecting: String.to_integer(id))}
  end

  def handle_event("cancel_reject", _params, socket) do
    {:noreply, assign(socket, rejecting: nil)}
  end

  def handle_event("submit_reject", %{"location_id" => id, "reason" => reason}, socket) do
    case find_location(socket, id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "That submission is no longer in the queue.")
         |> assign(rejecting: nil)}

      location ->
        case Reports.reject_location(location, reason) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "#{location.name} rejected.")
             |> assign(rejecting: nil)
             |> refresh_pending()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Couldn't reject that location.")}
        end
    end
  end

  def handle_event("clear_outage", %{"id" => id}, socket) do
    {:noreply, clear(socket, socket.assigns.flagged.outages, id, &Reports.clear_outage_flag/1)}
  end

  def handle_event("clear_price", %{"id" => id}, socket) do
    {:noreply, clear(socket, socket.assigns.flagged.prices, id, &Reports.clear_price_flag/1)}
  end

  defp find_location(socket, id) do
    id = String.to_integer(id)
    Enum.find(socket.assigns.pending_locations, &(&1.id == id))
  end

  defp refresh_pending(socket), do: assign(socket, pending_locations: Reports.list_pending_locations())

  defp clear(socket, reports, id, clear_fun) do
    id = String.to_integer(id)

    case Enum.find(reports, &(&1.id == id)) do
      nil ->
        put_flash(socket, :error, "That report is no longer in the queue.")

      report ->
        case clear_fun.(report) do
          {:ok, _} -> refresh(socket)
          {:error, _} -> put_flash(socket, :error, "Couldn't clear that flag.")
        end
    end
  end

  defp refresh(socket), do: assign(socket, flagged: Reports.list_flagged_reports())

  defp reporter_name(%{reported_by: %{username: username}}), do: username
  defp reporter_name(_), do: "anonymous"

  defp submitter_name(%{submitted_by: %{username: username}}), do: username
  defp submitter_name(_), do: "unknown"

  defp blank_dash(""), do: "—"
  defp blank_dash(reason), do: reason

  defp commodity_summary(%{commodity: "other", commodity_other: other}) when other != "", do: other
  defp commodity_summary(%{commodity: commodity}), do: PriceReport.commodity_label(commodity)

  defp group_label("residential"), do: "residential"
  defp group_label("market"), do: "market"
  defp group_label(other), do: other
end
