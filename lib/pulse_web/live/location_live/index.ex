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

  import PulseWeb.ReportFormat,
    only: [
      utility_label: 1,
      status_word: 1,
      status_class: 2,
      status_dot_class: 2,
      recent?: 2,
      time_ago: 2,
      full_time: 1,
      people: 1
    ]

  alias Pulse.Reports
  alias Pulse.Reports.Location

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

      <.link
        navigate={~p"/prices"}
        class="group mt-6 flex items-center justify-between gap-4 rounded-lg border border-line bg-paper-raised px-4 py-3 hover:border-copper"
      >
        <span>
          <span class="font-semibold text-ink">Compare prices</span>
          <span class="block text-sm text-ink-soft">
            Mealie meal, cooking oil, charcoal and more, place by place
          </span>
        </span>
        <.icon
          name="hero-chevron-right-mini"
          class="flex-none text-ink-soft transition group-hover:translate-x-0.5 group-hover:text-copper-strong"
        />
      </.link>

      <p class="mt-4 text-sm">
        <.link href={~p"/locations/new"} class="font-semibold text-copper-strong hover:underline">
          Propose a location
        </.link>
        not listed here.
      </p>

      <div :if={@grouped == %{}} class="mt-8 text-ink-soft">
        No locations yet.
      </div>

      <div
        :for={type <- Location.location_types()}
        :if={@grouped[type]}
        id={"group-#{type}"}
        class="mt-8 scroll-mt-20"
      >
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
                <.row_summary
                  summary={@summaries[location.id]}
                  runs={@runs[location.id] || %{}}
                  now={@now}
                />
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
  attr :runs, :map, default: %{}
  attr :now, DateTime, required: true

  defp row_summary(%{summary: nil} = assigns) do
    ~H"""
    <p class="mt-0.5 text-sm text-ink-soft">No reports yet</p>
    """
  end

  # A row whose newest report is over three days old says so, rather
  # than listing "Power on · 1 Oct" as if it were news. Otherwise each
  # status gets a coloured dot (grey once it's over a day old) so the
  # list can be scanned at a glance.
  defp row_summary(assigns) do
    latest = latest_report_at(assigns.summary)
    assigns = assign(assigns, latest: latest, recent: recent?(latest, assigns.now))

    ~H"""
    <p :if={!@recent} class="mt-0.5 text-sm text-ink-soft" title={full_time(@latest)}>
      <span class="mr-1 inline-block h-2 w-2 rounded-full bg-ink-soft align-middle opacity-40" aria-hidden="true"></span>No recent reports · last report {time_ago(@latest, @now)}
    </p>
    <p :if={@recent} class="mt-0.5 flex flex-wrap gap-x-3 gap-y-0.5 text-sm text-ink-soft">
      <span :for={report <- @summary.outages} title={full_time(report.reported_at)}>
        <span
          class={["mr-1 inline-block h-2 w-2 rounded-full align-middle", status_dot_class(report, @now)]}
          aria-hidden="true"
        ></span><span class={["font-medium", status_class(report, @now)]}>
          {utility_label(report.utility)} {status_word(report.status)}
        </span>
        <span :if={crowd(@runs[report.utility]) >= 2}>
          · {people(crowd(@runs[report.utility]))}
        </span>
        · {time_ago(report.reported_at, @now)}
      </span>
      <span :if={@summary.prices_updated_at} title={full_time(@summary.prices_updated_at)}>
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
      runs: Reports.outage_runs(socket.assigns.location_ids),
      now: DateTime.utc_now()
    )
  end

  defp group_label("residential"), do: "Residential areas"
  defp group_label("market"), do: "Markets"
  defp group_label(other), do: other

  # How many people are behind the current status (see Reports.outage_runs/1).
  defp crowd(%{people: people}), do: people
  defp crowd(_), do: 0

  defp latest_report_at(%{outages: outages, prices_updated_at: prices_at}) do
    [prices_at | Enum.map(outages, & &1.reported_at)]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime)
  end
end
