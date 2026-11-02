defmodule PulseWeb.ReportFormat do
  @moduledoc """
  How reports are worded and timed everywhere they're shown — the home
  page rows (`LocationLive.Index`), the location page (`LocationLive.Show`)
  and the report/flag pages (`ReportHTML`) — so the same outage reads the
  same way on every page ("Power out", never "Electricity is down" on one
  page and "Power out" on another).

  ## Times

  Report times are stored in UTC. Pulse's users are in Lusaka, which is
  on Central Africa Time (UTC+2) all year round — Zambia doesn't observe
  daylight saving — so local time is a fixed two-hour shift, and no time
  zone database is needed.
  """

  alias Pulse.Reports.{OutageReport, PriceReport}

  @lusaka_offset_seconds 2 * 60 * 60

  # A report older than this is shown muted rather than in red/green —
  # "power out" from three days ago says little about right now.
  @stale_after_seconds 24 * 60 * 60

  ## Labels

  def utility_label(utility),
    do: if(utility == OutageReport.electricity(), do: "Power", else: "Water")

  def status_word(status), do: if(status == OutageReport.up(), do: "on", else: "out")

  @doc ~S|"Power out", "Water on".|
  def outage_short(%OutageReport{utility: utility, status: status}),
    do: "#{utility_label(utility)} #{status_word(status)}"

  def commodity_label(%PriceReport{commodity: "other", commodity_other: other}) when other != "",
    do: other

  def commodity_label(%PriceReport{commodity: commodity}), do: PriceReport.commodity_label(commodity)

  @doc ~S|"Mealie meal: K450.00 / 25kg bag".|
  def price_summary(%PriceReport{} = report),
    do: "#{commodity_label(report)}: K#{Decimal.to_string(report.price_kwacha)} / #{report.unit}"

  def reporter_name(%{reported_by: %{username: username}}), do: username
  def reporter_name(_), do: "anonymous"

  ## Status colour

  @doc "Teal for on, red for out, muted grey once the report is over a day old."
  def status_class(%OutageReport{} = report, %DateTime{} = now) do
    cond do
      stale?(report.reported_at, now) -> "text-ink-soft"
      report.status == OutageReport.up() -> "text-teal"
      true -> "text-danger"
    end
  end

  def stale?(%DateTime{} = reported_at, %DateTime{} = now),
    do: DateTime.diff(now, reported_at) > @stale_after_seconds

  ## Times

  @doc ~S|Compact, for the home page rows: "just now", "12 min ago", "3 h ago", "2 d ago", then "1 Oct".|
  def time_ago(%DateTime{} = then, %DateTime{} = now) do
    seconds = max(DateTime.diff(now, then), 0)

    cond do
      seconds < 60 -> "just now"
      seconds < 60 * 60 -> "#{div(seconds, 60)} min ago"
      seconds < 24 * 60 * 60 -> "#{div(seconds, 60 * 60)} h ago"
      seconds < 7 * 24 * 60 * 60 -> "#{div(seconds, 24 * 60 * 60)} d ago"
      true -> then |> to_lusaka() |> Calendar.strftime("%-d %b")
    end
  end

  @doc """
  Fuller, for the location page, in Lusaka time: "just now", "12 min ago",
  "today, 06:46", "yesterday, 18:20", "1 Oct, 06:46", or "1 Oct 2025, 06:46"
  for a previous year. Works without hovering, so it reads the same on a
  phone as on a desktop.
  """
  def reported_when(%DateTime{} = then, %DateTime{} = now) do
    seconds = max(DateTime.diff(now, then), 0)
    local = to_lusaka(then)
    local_now = to_lusaka(now)
    clock = Calendar.strftime(local, "%H:%M")

    cond do
      seconds < 60 ->
        "just now"

      seconds < 60 * 60 ->
        "#{div(seconds, 60)} min ago"

      DateTime.to_date(local) == DateTime.to_date(local_now) ->
        "today, #{clock}"

      DateTime.to_date(local) == Date.add(DateTime.to_date(local_now), -1) ->
        "yesterday, #{clock}"

      local.year == local_now.year ->
        Calendar.strftime(local, "%-d %b, %H:%M")

      true ->
        Calendar.strftime(local, "%-d %b %Y, %H:%M")
    end
  end

  @doc ~S|Full date and time in Lusaka time, for tooltips: "1 Oct 2026, 06:46 (Lusaka time)".|
  def full_time(%DateTime{} = dt),
    do: Calendar.strftime(to_lusaka(dt), "%-d %b %Y, %H:%M") <> " (Lusaka time)"

  defp to_lusaka(%DateTime{} = dt), do: DateTime.add(dt, @lusaka_offset_seconds, :second)
end
