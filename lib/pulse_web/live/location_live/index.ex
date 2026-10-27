defmodule PulseWeb.LocationLive.Index do
  @moduledoc """
  The locations list — the Elixir/LiveView equivalent of the React
  `LocationsPage.jsx`. Grouped by location type (residential areas vs
  markets) the same way the original did.

  Each row shows that location's latest power/water status and when
  prices were last reported, so the answer to "is the power out in
  Chilenje?" is on the home page itself rather than one click away. The
  page subscribes to every listed location's PubSub topic, so a report
  made anywhere updates its row live, and a once-a-minute tick keeps the
  "12 min ago" labels from going stale while the page sits open.

  All of this still renders on the initial (non-LiveView) page load, so
  the statuses show even where the live connection can't be established.
  """

  use PulseWeb, :live_view

  alias Pulse.Reports
  alias Pulse.Reports.{Location, OutageReport}

  # A report older than this is shown muted rather than in red/green —
  # "power out" from three days ago says little about right now.
  @stale_after_seconds 24 * 60 * 60

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        What's happening in Lusaka
        <:subtitle>
          Power, water and market price reports from people across Lusaka. Open a
          location for the details, or report what's happening where you are.
        </:subtitle>
      </.header>

      <p class="mt-4 text-sm">
        <.link navigate={~p"/locations/new"} class="font-semibold text-copper-strong hover:underline">
          Propose a location
        </.link>
        not listed here.
      </p>

      <div :if={@grouped == %{}} class="mt-8 text-ink-soft">
        No locations yet.
      </div>

      <div :for={type <- Location.location_types()} :if={@grouped[type]} class="mt-8">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          {group_label(type)}
        </h2>

        <ul class="mt-2 divide-y divide-line rounded-lg border border-line">
          <li :for={location <- @grouped[type]}>
            <.link
              navigate={~p"/locations/#{location.id}"}
              class="group flex items-center justify-between gap-4 px-4 py-3 hover:bg-paper-raised"
            >
              <div class="min-w-0">
                <p class="font-medium">{location.name}</p>
                <.row_summary summary={@summaries[location.id]} now={@now} />
              </div>
              <.icon
                name="hero-chevron-right-mini"
                class="flex-none text-ink-soft transition group-hover:translate-x-0.5 group-hover:text-copper-strong"
              />
            </.link>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :summary, :map, default: nil
  attr :now, DateTime, required: true

  defp row_summary(%{summary: nil} = assigns) do
    ~H"""
    <p class="mt-0.5 text-sm text-ink-soft">No reports yet</p>
    """
  end

  defp row_summary(assigns) do
    ~H"""
    <p class="mt-0.5 flex flex-wrap gap-x-3 gap-y-0.5 text-sm text-ink-soft">
      <span :for={report <- @summary.outages} title={format_time(report.reported_at)}>
        <span class={["font-medium", status_class(report, @now)]}>
          {utility_label(report.utility)} {status_word(report.status)}
        </span>
        · {time_ago(report.reported_at, @now)}
      </span>
      <span :if={@summary.prices_updated_at} title={format_time(@summary.prices_updated_at)}>
        Prices · {time_ago(@summary.prices_updated_at, @now)}
      </span>
    </p>
    """
  end

  def mount(_params, _session, socket) do
    locations = Reports.list_locations()

    if connected?(socket) do
      Enum.each(locations, &Reports.subscribe(&1.id))
      :timer.send_interval(:timer.minutes(1), :tick)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Locations",
       grouped: Enum.group_by(locations, & &1.location_type),
       location_ids: Enum.map(locations, & &1.id)
     )
     |> assign_summaries()}
  end

  # Broadcast by Pulse.Reports for new reports and for flags, on the
  # topic of the location they belong to.
  def handle_info({:report_created, _report}, socket) do
    {:noreply, assign_summaries(socket)}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, now: DateTime.utc_now())}
  end

  defp assign_summaries(socket) do
    assign(socket,
      summaries: Reports.location_summaries(socket.assigns.location_ids),
      now: DateTime.utc_now()
    )
  end

  defp group_label("residential"), do: "Residential areas"
  defp group_label("market"), do: "Markets"
  defp group_label(other), do: other

  defp utility_label(utility),
    do: if(utility == OutageReport.electricity(), do: "Power", else: "Water")

  defp status_word(status), do: if(status == OutageReport.up(), do: "on", else: "out")

  defp status_class(report, now) do
    cond do
      stale?(report.reported_at, now) -> "text-ink-soft"
      report.status == OutageReport.up() -> "text-teal"
      true -> "text-danger"
    end
  end

  defp stale?(reported_at, now), do: DateTime.diff(now, reported_at) > @stale_after_seconds

  defp time_ago(%DateTime{} = then, now) do
    seconds = max(DateTime.diff(now, then), 0)

    cond do
      seconds < 60 -> "just now"
      seconds < 60 * 60 -> "#{div(seconds, 60)} min ago"
      seconds < 24 * 60 * 60 -> "#{div(seconds, 60 * 60)} h ago"
      seconds < 7 * 24 * 60 * 60 -> "#{div(seconds, 24 * 60 * 60)} d ago"
      true -> Calendar.strftime(then, "%d %b")
    end
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%d %b %Y, %H:%M UTC")
end
