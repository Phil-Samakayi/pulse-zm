defmodule PulseWeb.LocationLive.Show do
  @moduledoc """
  A single location: its latest outage and price reports, plus the ways to
  add one. Subscribes to the location's PubSub topic on mount, so when
  *anyone* reports something here, every open tab updates immediately.

  Nothing on this page writes through the LiveView socket. The one-tap
  outage buttons are ordinary HTML forms posting to
  `PulseWeb.ReportController`, "Get alerts" / "Turn off" post to
  `PulseWeb.AlertController`, and "Add a note", "Report a price" and
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
        <:actions>
          <.link
            href={whatsapp_url(@share_text)}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1.5 rounded-full border border-line px-3 py-1.5 text-sm font-semibold text-ink hover:border-copper hover:text-copper-strong"
          >
            <.icon name="hero-share-mini" class="h-4 w-4" />
            <span><span class="hidden sm:inline">Share on </span>WhatsApp</span>
          </.link>
        </:actions>
      </.header>

      <section class="mt-6 grid grid-cols-2 gap-3" aria-label="Power and water right now">
        <.status_tile
          :for={utility <- OutageReport.utilities()}
          utility={utility}
          report={Enum.find(@latest_outages, &(&1.utility == utility))}
          run={@runs[utility]}
          location={@location}
          current_user={@current_user}
          now={@now}
        />
      </section>

      <.alert_toggle
        :if={@current_user && (@alerts_enabled or @following)}
        location={@location}
        following={@following}
      />

      <section
        :if={@current_user}
        class="mt-4 rounded-lg border border-line bg-paper-raised p-4"
        aria-labelledby="report-heading"
      >
        <h2 id="report-heading" class="text-sm font-semibold text-ink">
          {if @latest_outages == [], do: "What's happening here right now?", else: "Has something changed?"}
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
        class="mt-4 rounded-lg border border-line bg-paper-raised p-4 text-sm text-ink-soft"
      >
        <.link href={~p"/users/log_in"} class="font-semibold text-copper-strong hover:underline">
          Log in
        </.link>
        or
        <.link href={~p"/users/register"} class="font-semibold text-copper-strong hover:underline">
          sign up
        </.link>
        to report what's happening here or get alerts when it changes.
      </p>

      <section class="mt-8">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          Latest reports
        </h2>
        <.report_list
          reports={@latest_outages}
          type="outage"
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

  # "Get alerts" / "Alerts on · Turn off". Both are tap-only forms posting
  # to PulseWeb.AlertController. The "Get alerts" form carries
  # data-needs-push, so assets/js/app.js first asks for notification
  # permission and saves this browser's push subscription, showing any
  # problem in the data-push-status line, and only then submits it.
  attr :location, :any, required: true
  attr :following, :boolean, required: true

  defp alert_toggle(%{following: true} = assigns) do
    ~H"""
    <.form
      for={%{}}
      action={~p"/alerts/locations/#{@location.id}"}
      method="delete"
      class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm"
    >
      <span class="inline-flex items-center gap-1.5 font-semibold text-teal">
        <.icon name="hero-bell-alert-mini" class="h-4 w-4" /> Alerts on
      </span>
      <button type="submit" class="text-ink-soft hover:text-copper-strong hover:underline">
        Turn off
      </button>
    </.form>
    """
  end

  defp alert_toggle(assigns) do
    ~H"""
    <.form
      for={%{}}
      action={~p"/alerts/locations/#{@location.id}"}
      method="post"
      data-needs-push="true"
      class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1"
    >
      <button
        type="submit"
        class="inline-flex items-center gap-1.5 rounded-full border border-line px-3 py-1.5 text-sm font-semibold text-ink hover:border-copper hover:text-copper-strong"
      >
        <.icon name="hero-bell-mini" class="h-4 w-4" /> Get alerts for {@location.name}
      </button>
      <p data-push-status aria-live="polite" class="text-xs text-ink-soft">
        A notification when power or water changes here.
      </p>
    </.form>
    """
  end

  attr :reports, :list, required: true
  attr :type, :string, required: true
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
          <p :if={report.note != ""} class="mt-1 text-sm text-ink">{report.note}</p>
        </div>

        <div :if={@current_user} class="-mr-2 flex shrink-0 flex-col items-end gap-1">
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

  # One tile per utility at the top of the page — the answer to "is the
  # power out here?" before anything else. "OUT, since today, 06:46,
  # reported by 14 people", with Me too right there. A report over a day
  # old is shown muted; one over three days old (or none at all) reads
  # "No recent report", since it says nothing about right now.
  attr :utility, :string, required: true
  attr :report, :any, default: nil
  attr :run, :map, default: nil
  attr :location, :any, required: true
  attr :current_user, :any, required: true
  attr :now, DateTime, required: true

  defp status_tile(assigns) do
    %{report: report, run: run, now: now} = assigns

    state =
      cond do
        is_nil(report) or not recent?(report.reported_at, now) -> :none
        stale?(report.reported_at, now) -> :stale
        report.status == OutageReport.up() -> :on
        true -> :out
      end

    {since, people} =
      case run do
        %{people: people, since: since} when people > 0 -> {since, people}
        _ -> {report && report.reported_at, 0}
      end

    assigns = assign(assigns, state: state, since: since, people: people)

    ~H"""
    <div class={["rounded-xl p-3", tile_class(@state)]}>
      <p class="text-sm font-semibold">{utility_label(@utility)}</p>

      <div :if={@state == :none}>
        <p class="mt-1 font-bold leading-tight">No recent report</p>
        <p :if={@report} class="mt-1 text-xs">Last: {reported_when(@report.reported_at, @now)}</p>
        <p :if={!@report} class="mt-1 text-xs">Nobody has reported here yet</p>
      </div>

      <div :if={@state != :none}>
        <p class="mt-0.5 text-2xl font-extrabold uppercase leading-none">
          {status_word(@report.status)}
        </p>
        <p class="mt-1.5 text-xs">Since {reported_when(@since, @now)}</p>
        <p :if={@people > 0} class="text-xs">reported by {people(@people)}</p>
        <div :if={@current_user} class="mt-2">
          <.me_too report={@report} run={@run} location={@location} current_user={@current_user} />
        </div>
      </div>
    </div>
    """
  end

  defp tile_class(:out), do: "bg-danger-bg text-danger"
  defp tile_class(:on), do: "bg-teal-bg text-teal"
  defp tile_class(:stale), do: "border border-line bg-paper-raised text-ink-soft"
  defp tile_class(:none), do: "border border-dashed border-line bg-paper-raised text-ink-soft"

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
      class="py-1 text-xs font-medium"
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
        class="rounded-full border border-line bg-paper-raised px-3 py-1 text-xs font-semibold text-ink hover:border-copper hover:text-copper-strong"
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
       |> assign(
         following: Pulse.Alerts.following_location?(socket.assigns.current_user, location.id),
         alerts_enabled: Pulse.Push.enabled?()
       )
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

    location = socket.assigns.location
    runs = Map.get(Reports.outage_runs([location.id]), location.id, %{})
    now = DateTime.utc_now()

    share_text =
      share_text(
        location,
        status.latest_outages,
        runs,
        status.latest_prices,
        url(~p"/locations/#{location.id}"),
        now
      )

    assign(socket,
      latest_outages: status.latest_outages,
      latest_prices: status.latest_prices,
      runs: runs,
      share_text: share_text,
      now: now
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
