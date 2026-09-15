defmodule PulseWeb.LocationLive.Show do
  @moduledoc """
  A single location: its latest outage/price reports, and — if you're
  logged in — forms to add a new one. Subscribes to that location's
  PubSub topic on mount, so the moment *anyone* submits a report here,
  every browser tab looking at this page updates immediately. That's
  the thing the original React app couldn't do without polling.
  """

  use PulseWeb, :live_view

  alias Pulse.Reports
  alias Pulse.Reports.{OutageReport, PriceReport}

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.back navigate={~p"/"}>All locations</.back>

      <.header class="mt-4">
        {@location.name}
        <:subtitle>{@location.city} · {group_label(@location.location_type)}</:subtitle>
      </.header>

      <section class="mt-8">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          Power &amp; water
        </h2>
        <.report_list
          reports={@latest_outages}
          type="outage"
          flagging={@flagging}
          current_user={@current_user}
          empty_text="No outage reports yet — be the first to report one."
        >
          <:summary :let={report}>
            {utility_label(report.utility)} is
            <span class={if report.status == "up", do: "text-teal", else: "text-danger"}>
              {status_label(report.status)}
            </span>
          </:summary>
        </.report_list>
      </section>

      <section class="mt-8">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          Market prices
        </h2>
        <.report_list
          reports={@latest_prices}
          type="price"
          flagging={@flagging}
          current_user={@current_user}
          empty_text="No price reports yet — be the first to report one."
        >
          <:summary :let={report}>
            {commodity_label(report)}: K{Decimal.to_string(report.price_kwacha)} / {report.unit}
          </:summary>
        </.report_list>
      </section>

      <section :if={@current_user} class="mt-10">
        <div class="flex gap-1 border-b border-line">
          <button
            type="button"
            phx-click="switch_report_tab"
            phx-value-tab="outage"
            class={[
              "-mb-px border-b-2 px-4 py-2 text-sm font-semibold",
              if(@report_tab == "outage",
                do: "border-copper text-copper-strong",
                else: "border-transparent text-ink-soft hover:text-ink"
              )
            ]}
          >
            Report an outage
          </button>
          <button
            type="button"
            phx-click="switch_report_tab"
            phx-value-tab="price"
            class={[
              "-mb-px border-b-2 px-4 py-2 text-sm font-semibold",
              if(@report_tab == "price",
                do: "border-copper text-copper-strong",
                else: "border-transparent text-ink-soft hover:text-ink"
              )
            ]}
          >
            Report a price
          </button>
        </div>

        <div :if={@report_tab == "outage"} class="mt-6 max-w-sm">
          <.simple_form
            for={@outage_form}
            id="outage_form"
            phx-change="validate_outage"
            phx-submit="submit_outage"
          >
            <.input
              field={@outage_form[:utility]}
              type="select"
              label="Utility"
              prompt="Choose one"
              options={utility_options()}
            />
            <.input
              field={@outage_form[:status]}
              type="select"
              label="Status"
              prompt="Choose one"
              options={status_options()}
            />
            <.input field={@outage_form[:note]} type="textarea" label="Note (optional)" />
            <:actions>
              <.button phx-disable-with="Submitting..." class="w-full">Submit</.button>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@report_tab == "price"} class="mt-6 max-w-sm">
          <.simple_form
            for={@price_form}
            id="price_form"
            phx-change="validate_price"
            phx-submit="submit_price"
          >
            <.input
              field={@price_form[:commodity]}
              type="select"
              label="Commodity"
              prompt="Choose one"
              options={commodity_options()}
            />
            <.input
              :if={@price_form[:commodity].value == "other"}
              field={@price_form[:commodity_other]}
              type="text"
              label="What is it?"
            />
            <.input field={@price_form[:unit]} type="text" label="Unit (e.g. 25kg bag, litre)" />
            <.input field={@price_form[:price_kwacha]} type="number" label="Price (ZMW)" step="0.01" />
            <.input field={@price_form[:note]} type="textarea" label="Note (optional)" />
            <:actions>
              <.button phx-disable-with="Submitting..." class="w-full">Submit</.button>
            </:actions>
          </.simple_form>
        </div>
      </section>

      <p :if={!@current_user} class="mt-10 text-sm text-ink-soft">
        <.link navigate={~p"/users/log_in"} class="font-semibold text-copper-strong hover:underline">
          Log in
        </.link>
        to submit a report.
      </p>
    </div>
    """
  end

  attr :reports, :list, required: true
  attr :type, :string, required: true
  attr :flagging, :any, required: true
  attr :current_user, :any, required: true
  attr :empty_text, :string, required: true
  slot :summary, required: true

  defp report_list(assigns) do
    ~H"""
    <p :if={@reports == []} class="mt-2 text-sm text-ink-soft">{@empty_text}</p>

    <ul :if={@reports != []} class="mt-2 divide-y divide-line rounded-lg border border-line">
      <li :for={report <- @reports} class="px-4 py-3">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="font-medium">{render_slot(@summary, report)}</p>
            <p class="mt-1 text-xs text-ink-soft">
              {reporter_name(report)} · {format_time(report.reported_at)}
              <span :if={report.is_flagged} class="ml-1 text-amber">· flagged for review</span>
            </p>
            <p :if={report.note != ""} class="mt-1 text-sm text-ink">{report.note}</p>
          </div>

          <button
            :if={@current_user && @flagging != {@type, report.id}}
            type="button"
            phx-click="start_flag"
            phx-value-type={@type}
            phx-value-id={report.id}
            class="shrink-0 text-xs text-ink-soft hover:text-copper-strong hover:underline"
          >
            Flag
          </button>
        </div>

        <form
          :if={@flagging == {@type, report.id}}
          phx-submit="submit_flag"
          class="mt-3 flex items-center gap-2"
        >
          <input type="hidden" name="type" value={@type} />
          <input type="hidden" name="report_id" value={report.id} />
          <input
            type="text"
            name="reason"
            placeholder="Why is this wrong? (optional)"
            class="flex-1 rounded-md border-line text-sm focus:border-teal focus:ring-0"
          />
          <button type="submit" class="text-xs font-semibold text-danger hover:underline">
            Confirm flag
          </button>
          <button type="button" phx-click="cancel_flag" class="text-xs text-ink-soft hover:underline">
            Cancel
          </button>
        </form>
      </li>
    </ul>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    location = Reports.get_location!(id)

    if connected?(socket) do
      Reports.subscribe(location.id)
    end

    {:ok,
     socket
     |> assign(location: location, page_title: location.name, flagging: nil, report_tab: "outage")
     |> assign_status()
     |> assign_outage_form(Reports.change_outage_report())
     |> assign_price_form(Reports.change_price_report())}
  end

  def handle_info({:report_created, _report}, socket) do
    {:noreply, assign_status(socket)}
  end

  def handle_event("switch_report_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, report_tab: tab)}
  end

  def handle_event("validate_outage", %{"outage_report" => params}, socket) do
    changeset = Reports.change_outage_report(params) |> Map.put(:action, :validate)
    {:noreply, assign_outage_form(socket, changeset)}
  end

  def handle_event("submit_outage", %{"outage_report" => params}, socket) do
    with_current_user(socket, fn user ->
      attrs =
        params
        |> Map.put("location_id", socket.assigns.location.id)
        |> Map.put("reported_by_id", user.id)

      case Reports.create_outage_report(attrs) do
        {:ok, _report} ->
          socket
          |> put_flash(:info, "Thanks — outage report submitted.")
          |> assign_status()
          |> assign_outage_form(Reports.change_outage_report())

        {:error, changeset} ->
          apply_submit_error(socket, changeset, &assign_outage_form/2)
      end
    end)
  end

  def handle_event("validate_price", %{"price_report" => params}, socket) do
    changeset = Reports.change_price_report(params) |> Map.put(:action, :validate)
    {:noreply, assign_price_form(socket, changeset)}
  end

  def handle_event("submit_price", %{"price_report" => params}, socket) do
    with_current_user(socket, fn user ->
      attrs =
        params
        |> Map.put("location_id", socket.assigns.location.id)
        |> Map.put("reported_by_id", user.id)

      case Reports.create_price_report(attrs) do
        {:ok, _report} ->
          socket
          |> put_flash(:info, "Thanks — price report submitted.")
          |> assign_status()
          |> assign_price_form(Reports.change_price_report())

        {:error, changeset} ->
          apply_submit_error(socket, changeset, &assign_price_form/2)
      end
    end)
  end

  def handle_event("start_flag", %{"type" => type, "id" => id}, socket) do
    {:noreply, assign(socket, flagging: {type, String.to_integer(id)})}
  end

  def handle_event("cancel_flag", _params, socket) do
    {:noreply, assign(socket, flagging: nil)}
  end

  def handle_event("submit_flag", %{"type" => type, "report_id" => id, "reason" => reason}, socket) do
    with_current_user(socket, fn _user ->
      id = String.to_integer(id)
      attrs = %{"flag_reason" => reason}

      result =
        case type do
          "outage" -> find_report(socket.assigns.latest_outages, id) |> flag(:outage, attrs)
          "price" -> find_report(socket.assigns.latest_prices, id) |> flag(:price, attrs)
        end

      case result do
        {:ok, _report} ->
          socket |> put_flash(:info, "Thanks — flagged for review.") |> assign(flagging: nil) |> assign_status()

        _ ->
          socket |> put_flash(:error, "Couldn't flag that report.") |> assign(flagging: nil)
      end
    end)
  end

  defp flag(nil, _kind, _attrs), do: :error
  defp flag(report, :outage, attrs), do: Reports.flag_outage_report(report, attrs)
  defp flag(report, :price, attrs), do: Reports.flag_price_report(report, attrs)

  defp find_report(reports, id), do: Enum.find(reports, &(&1.id == id))

  defp with_current_user(socket, fun) do
    case socket.assigns.current_user do
      nil -> {:noreply, put_flash(socket, :error, "Log in to do that.")}
      user -> {:noreply, fun.(user)}
    end
  end

  defp apply_submit_error(socket, changeset, assign_fn) do
    case Keyword.get(changeset.errors, :base) do
      {_message, _opts} = error ->
        socket
        |> put_flash(:error, translate_error(error))
        |> assign_fn.(changeset)

      nil ->
        assign_fn.(socket, changeset)
    end
  end

  defp assign_status(socket) do
    status = Reports.location_status(socket.assigns.location)
    assign(socket, latest_outages: status.latest_outages, latest_prices: status.latest_prices)
  end

  defp assign_outage_form(socket, changeset) do
    assign(socket, outage_form: to_form(changeset, as: "outage_report"))
  end

  defp assign_price_form(socket, changeset) do
    assign(socket, price_form: to_form(changeset, as: "price_report"))
  end

  defp reporter_name(%{reported_by: %{username: username}}), do: username
  defp reporter_name(_), do: "anonymous"

  defp format_time(nil), do: ""
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%d %b %Y, %H:%M UTC")

  defp group_label("residential"), do: "Residential area"
  defp group_label("market"), do: "Market"
  defp group_label(other), do: other

  defp utility_label(u), do: if(u == OutageReport.electricity(), do: "Electricity", else: "Water")
  defp status_label(s), do: if(s == OutageReport.up(), do: "up", else: "down")

  defp commodity_label(%PriceReport{commodity: "other", commodity_other: other}) when other != "",
    do: other

  defp commodity_label(%PriceReport{commodity: commodity}), do: PriceReport.commodity_label(commodity)

  defp utility_options, do: Enum.map(OutageReport.utilities(), &{utility_label(&1), &1})
  defp status_options, do: Enum.map(OutageReport.statuses(), &{status_label(&1), &1})
  defp commodity_options, do: Enum.map(PriceReport.commodities(), &{PriceReport.commodity_label(&1), &1})
end
