defmodule PulseWeb.LocationLive.Show do
  @moduledoc """
  A single location: its latest outage and price reports, plus the ways to
  add one. Subscribes to the location's PubSub topic on mount, so when
  *anyone* reports something here, every open tab updates immediately.

  Nothing on this page writes through the LiveView socket. The one-tap
  outage buttons are ordinary HTML forms posting to
  `PulseWeb.ReportController`, and "Add a note", "Report a price" and
  "Flag" link to ordinary controller-rendered pages. So reporting works
  even where the live connection can't stay up (Render's free plan —
  see the project's hosting notes): the page fully renders on the first
  HTTP response, a form submit is a normal POST, and the live updates
  are a bonus on top rather than something reporting depends on. It's the
  same reason login and registration are plain controller pages.

  A location that's still pending review (or was rejected) is only shown
  to admins, who need to open it from the moderation queue. Everyone else
  is sent home with a flash.
  """

  use PulseWeb, :live_view

  import PulseWeb.ReportFormat

  alias Pulse.Reports
  alias Pulse.Reports.OutageReport

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.link
        navigate={~p"/"}
        class="text-sm font-semibold leading-6 text-copper-strong hover:text-copper"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> All locations
      </.link>

      <.header class="mt-4">
        {@location.name}
        <:subtitle>{@location.city} · {group_label(@location.location_type)}</:subtitle>
      </.header>

      <section
        :if={@current_user}
        class="mt-6 rounded-lg border border-line bg-paper-raised p-4"
        aria-labelledby="report-heading"
      >
        <h2 id="report-heading" class="text-sm font-semibold text-ink">
          What's happening here right now?
        </h2>

        <div class="mt-3 grid grid-cols-2 gap-2">
          <.form
            :for={{utility, status} <- quick_reports()}
            for={%{}}
            as={:outage_report}
            action={~p"/locations/#{@location.id}/outages"}
            method="post"
            class="contents"
          >
            <input type="hidden" name="outage_report[utility]" value={utility} />
            <input type="hidden" name="outage_report[status]" value={status} />
            <button
              type="submit"
              class={[
                "rounded-lg border px-3 py-3 text-sm font-semibold",
                if(status == OutageReport.up(),
                  do: "border-teal text-teal hover:bg-teal-bg",
                  else: "border-danger text-danger hover:bg-danger-bg"
                )
              ]}
            >
              {utility_label(utility)} {status_word(status)}
            </button>
          </.form>
        </div>

        <p class="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm">
          <.link
            href={~p"/locations/#{@location.id}/report/outage"}
            class="font-semibold text-copper-strong hover:underline"
          >
            Report with a note
          </.link>
          <.link
            href={~p"/locations/#{@location.id}/report/price"}
            class="font-semibold text-copper-strong hover:underline"
          >
            Report a price
          </.link>
        </p>
      </section>

      <p
        :if={!@current_user}
        class="mt-6 rounded-lg border border-line bg-paper-raised p-4 text-sm text-ink-soft"
      >
        <.link href={~p"/users/log_in"} class="font-semibold text-copper-strong hover:underline">
          Log in
        </.link>
        or
        <.link href={~p"/users/register"} class="font-semibold text-copper-strong hover:underline">
          sign up
        </.link>
        to report what's happening here.
      </p>

      <section class="mt-8">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          Power &amp; water
        </h2>
        <.report_list
          reports={@latest_outages}
          type="outage"
          runs={@runs}
          location={@location}
          current_user={@current_user}
          now={@now}
          empty_text="No power or water reports yet."
        >
          <:summary :let={report}>
            {utility_label(report.utility)} is
            <span class={status_class(report, @now)}>{status_word(report.status)}</span>
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
          location={@location}
          current_user={@current_user}
          now={@now}
          empty_text="No price reports yet."
        >
          <:summary :let={report}>{price_summary(report)}</:summary>
        </.report_list>
      </section>
    </div>
    """
  end

  attr :reports, :list, required: true
  attr :type, :string, required: true
  attr :runs, :map, default: %{}, doc: "outage runs by utility, from Reports.outage_runs/1"
  attr :location, :any, required: true
  attr :current_user, :any, required: true
  attr :now, DateTime, required: true
  attr :empty_text, :string, required: true
  slot :summary, required: true

  defp report_list(assigns) do
    ~H"""
    <p :if={@reports == []} class="mt-2 text-sm text-ink-soft">{@empty_text}</p>

    <ul :if={@reports != []} class="mt-2 divide-y divide-line rounded-lg border border-line">
      <li :for={report <- @reports} class="flex items-start justify-between gap-4 px-4 py-3">
        <div class="min-w-0">
          <p class="font-medium">{render_slot(@summary, report)}</p>
          <p class="mt-1 text-xs text-ink-soft" title={full_time(report.reported_at)}>
            {reporter_name(report)} · {reported_when(report.reported_at, @now)}
            <span :if={report.is_flagged} class="text-amber">· flagged for review</span>
          </p>
          <.run_line :if={@type == "outage"} run={@runs[report.utility]} now={@now} />
          <p :if={report.note != ""} class="mt-1 text-sm text-ink">{report.note}</p>
        </div>

        <div :if={@current_user} class="-mr-2 flex shrink-0 flex-col items-end gap-1">
          <.me_too
            :if={@type == "outage"}
            report={report}
            run={@runs[report.utility]}
            location={@location}
            current_user={@current_user}
          />
          <.link
            :if={!report.is_flagged}
            href={~p"/locations/#{@location.id}/flag/#{@type}/#{report.id}"}
            class="rounded px-2 py-1 text-xs text-ink-soft hover:bg-paper hover:text-copper-strong"
          >
            Flag
          </.link>
        </div>
      </li>
    </ul>
    """
  end

  # "Since Monday 06:46 · reported by 14 people" under the latest outage
  # report — only when there's more to say than the report itself does.
  attr :run, :map, default: nil
  attr :now, DateTime, required: true

  defp run_line(%{run: nil} = assigns), do: ~H""

  defp run_line(assigns) do
    ~H"""
    <p
      :if={@run.people > 0 and (@run.people >= 2 or @run.since != @run.latest_at)}
      class="mt-1 text-xs text-ink-soft"
    >
      Since {reported_when(@run.since, @now)} · reported by {people(@run.people)}
    </p>
    """
  end

  # "Me too": one tap re-reports the current status, adding this user to
  # the run's count. A tap-only form like the quick buttons above, so it
  # works without the live connection. Shown as "You reported this" once
  # the user is already counted.
  attr :report, :any, required: true
  attr :run, :map, default: nil
  attr :location, :any, required: true
  attr :current_user, :any, required: true

  defp me_too(assigns) do
    ~H"""
    <span
      :if={@run && MapSet.member?(@run.reporter_ids, @current_user.id)}
      class="px-2 py-1 text-xs text-ink-soft"
    >
      You reported this
    </span>
    <.form
      :if={!(@run && MapSet.member?(@run.reporter_ids, @current_user.id))}
      for={%{}}
      as={:outage_report}
      action={~p"/locations/#{@location.id}/outages"}
      method="post"
    >
      <input type="hidden" name="outage_report[utility]" value={@report.utility} />
      <input type="hidden" name="outage_report[status]" value={@report.status} />
      <button
        type="submit"
        class="rounded-full border border-line px-3 py-1 text-xs font-semibold text-ink hover:border-copper hover:text-copper-strong"
      >
        Me too
      </button>
    </.form>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    location = Reports.get_location!(id)

    if Reports.visible_to?(location, socket.assigns.current_user) do
      if connected?(socket) do
        Reports.subscribe(location.id)
        :timer.send_interval(:timer.minutes(1), :tick)
      end

      {:ok,
       socket
       |> assign(location: location, page_title: location.name)
       |> assign_status()}
    else
      {:ok,
       socket
       |> put_flash(:error, "That location isn't available yet.")
       |> push_navigate(to: ~p"/")}
    end
  end

  # Broadcast by Pulse.Reports for new reports and for flags.
  def handle_info({:report_created, _report}, socket) do
    {:noreply, assign_status(socket)}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, now: DateTime.utc_now())}
  end

  defp assign_status(socket) do
    status = Reports.location_status(socket.assigns.location)

    location_id = socket.assigns.location.id

    assign(socket,
      latest_outages: status.latest_outages,
      latest_prices: status.latest_prices,
      runs: Map.get(Reports.outage_runs([location_id]), location_id, %{}),
      now: DateTime.utc_now()
    )
  end

  defp quick_reports do
    for utility <- OutageReport.utilities(),
        status <- [OutageReport.up(), OutageReport.down()],
        do: {utility, status}
  end

  defp group_label("residential"), do: "Residential area"
  defp group_label("market"), do: "Market"
  defp group_label(other), do: other
end
