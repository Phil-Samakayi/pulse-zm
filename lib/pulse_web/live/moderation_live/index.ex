defmodule PulseWeb.ModerationLive.Index do
  @moduledoc """
  Admin-only moderation queue: every flagged outage/price report, with a
  button to clear the flag once it's been reviewed. Gated by the
  `:ensure_admin` on_mount hook — see `PulseWeb.UserAuth` and the router.
  """

  use PulseWeb, :live_view

  alias Pulse.Reports
  alias Pulse.Reports.PriceReport

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl">
      <.header>
        Moderation queue
        <:subtitle>Reports the community has flagged as inaccurate or abusive.</:subtitle>
      </.header>

      <section class="mt-8">
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
    {:ok, assign(socket, flagged: Reports.list_flagged_reports(), page_title: "Moderation")}
  end

  def handle_event("clear_outage", %{"id" => id}, socket) do
    {:noreply, clear(socket, socket.assigns.flagged.outages, id, &Reports.clear_outage_flag/1)}
  end

  def handle_event("clear_price", %{"id" => id}, socket) do
    {:noreply, clear(socket, socket.assigns.flagged.prices, id, &Reports.clear_price_flag/1)}
  end

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

  defp blank_dash(""), do: "—"
  defp blank_dash(reason), do: reason

  defp commodity_summary(%{commodity: "other", commodity_other: other}) when other != "", do: other
  defp commodity_summary(%{commodity: commodity}), do: PriceReport.commodity_label(commodity)
end
