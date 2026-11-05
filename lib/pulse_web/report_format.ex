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

  @doc ~S|"1 person", "14 people".|
  def people(1), do: "1 person"
  def people(n) when is_integer(n), do: "#{n} people"

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

  @doc """
  The coloured dot before a status: teal for on, red for out, faded grey
  once the report is over a day old (the same rule as `status_class/2`).
  """
  def status_dot_class(%OutageReport{} = report, %DateTime{} = now) do
    cond do
      stale?(report.reported_at, now) -> "bg-ink-soft opacity-40"
      report.status == OutageReport.up() -> "bg-teal"
      true -> "bg-danger"
    end
  end

  # Past this, a report says nothing about right now: a home page row whose
  # reports are all older reads "No recent reports · last 1 Oct" instead
  # of listing them as if they were news, and the location page's tiles
  # say "No recent report".
  @recent_seconds 3 * 24 * 60 * 60

  @doc "Whether a report time is recent enough (3 days) to describe right now."
  def recent?(%DateTime{} = reported_at, %DateTime{} = now),
    do: DateTime.diff(now, reported_at) <= @recent_seconds

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

  @doc "The date in Lusaka at that moment (which may be a day after the UTC date)."
  def lusaka_date(%DateTime{} = dt), do: dt |> to_lusaka() |> DateTime.to_date()

  @doc ~S|Weekday and clock time in Lusaka time: "Thu 18:20".|
  def day_time(%DateTime{} = dt), do: dt |> to_lusaka() |> Calendar.strftime("%a %H:%M")

  @doc ~S|A length of time, rounded: "45 min", "31 h".|
  def duration(seconds) when is_integer(seconds) and seconds < 60 * 60,
    do: "#{max(div(seconds, 60), 1)} min"

  def duration(seconds) when is_integer(seconds), do: "#{div(seconds + 30 * 60, 60 * 60)} h"

  @doc """
  The week shown by the outage strip: from midnight six days ago to the
  coming midnight, in Lusaka time, as `{start, stop}` in UTC. Seven whole
  days, so each day gets an equal slice of the strip and today's ends at
  the right edge.
  """
  def week_window(%DateTime{} = now) do
    today = now |> to_lusaka() |> DateTime.to_date()

    start =
      today
      |> Date.add(-6)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      |> DateTime.add(-@lusaka_offset_seconds, :second)

    {start, DateTime.add(start, 7 * 24 * 60 * 60, :second)}
  end

  @doc ~S|Labels for the strip's seven days, oldest first: ["Thu", "Fri", …, "Today"].|
  def week_days(%DateTime{} = window_start) do
    for day <- 0..6 do
      if day == 6,
        do: "Today",
        else: window_start |> DateTime.add(day * 24 * 60 * 60, :second) |> to_lusaka() |> Calendar.strftime("%a")
    end
  end

  @doc """
  What tapping a red stretch on the strip says: "Out 12 h · Thu 18:20 →
  Fri 06:10", or "Out since Wed 10:55 · 3 h so far" while it's still out.
  """
  def outage_tip(%{from: from, to: to}, %DateTime{} = now) do
    length = duration(DateTime.diff(to, from))

    if DateTime.compare(to, now) == :eq,
      do: "Out since #{day_time(from)} · #{length} so far",
      else: "Out #{length} · #{day_time(from)} → #{day_time(to)}"
  end

  @doc ~S|Full date and time in Lusaka time, for tooltips: "1 Oct 2026, 06:46 (Lusaka time)".|
  def full_time(%DateTime{} = dt),
    do: Calendar.strftime(to_lusaka(dt), "%-d %b %Y, %H:%M") <> " (Lusaka time)"

  ## Sharing

  @doc """
  The WhatsApp message for a location, e.g.

      *Kabwata* on Pulse
      • Power out since today, 06:46 · 14 people
      • Water on · yesterday, 18:20
      • Mealie meal: K450.00 / 25kg bag · 1 Oct, 09:10
      https://pulse-zm.onrender.com/locations/1

  `runs` is that location's map from `Pulse.Reports.outage_runs/1`.
  `*…*` is WhatsApp's bold.
  """
  def share_text(location, outages, runs, prices, url, %DateTime{} = now) do
    lines =
      Enum.map(outages, &outage_share_line(&1, runs[&1.utility], now)) ++
        Enum.map(prices, &"#{price_summary(&1)} · #{reported_when(&1.reported_at, now)}")

    body =
      case lines do
        [] -> ["No reports yet. Add one:"]
        lines -> Enum.map(lines, &("• " <> &1))
      end

    Enum.join(["*#{location.name}* on Pulse"] ++ body ++ [url], "\n")
  end

  @doc """
  One line for a location's link preview (`og:description`), e.g.
  "Power out since today, 06:46 · 14 people. Water on · yesterday, 18:20."
  """
  def status_summary(outages, runs, %DateTime{} = now) do
    case outages do
      [] -> "No reports yet. See what's happening here, or add the first report."
      outages -> Enum.map_join(outages, ". ", &outage_share_line(&1, runs[&1.utility], now)) <> "."
    end
  end

  defp outage_share_line(report, %{people: people, since: since}, now) when people >= 2,
    do: "#{outage_short(report)} since #{reported_when(since, now)} · #{people(people)}"

  defp outage_share_line(report, _run, now),
    do: "#{outage_short(report)} · #{reported_when(report.reported_at, now)}"

  @doc """
  The WhatsApp message for one item's price comparison, e.g.

      *Mealie meal (25kg bag)* prices on Pulse
      • K420.00 at City Market · today, 09:10
      • K450.00 at Soweto Market · yesterday, 16:30
      https://pulse-zm.onrender.com/prices/mealie_meal

  `reports` is that item's list from `Pulse.Reports.price_board/1`
  (cheapest first, each with its `:location` preloaded).
  """
  def price_share_text(commodity, reports, url, %DateTime{} = now) do
    body =
      case reports do
        [] ->
          ["No prices reported in the last two weeks. Add one:"]

        reports ->
          Enum.map(reports, fn report ->
            "• #{kwacha(report.price_kwacha)} at #{report.location.name} · " <>
              reported_when(report.reported_at, now)
          end)
      end

    Enum.join(["*#{item_with_unit(commodity)}* prices on Pulse"] ++ body ++ [url], "\n")
  end

  @doc ~S|"K420.00".|
  def kwacha(%Decimal{} = amount), do: "K" <> Decimal.to_string(amount)

  @doc ~S|"Mealie meal (25kg bag)", or just the item name if it has no standard unit.|
  def item_with_unit(commodity) do
    case PriceReport.standard_unit(commodity) do
      nil -> PriceReport.commodity_label(commodity)
      unit -> "#{PriceReport.commodity_label(commodity)} (#{unit})"
    end
  end

  @doc "A wa.me link that opens WhatsApp (app or web) with `text` ready to send."
  def whatsapp_url(text), do: "https://wa.me/?text=" <> URI.encode(text, &URI.char_unreserved?/1)

  defp to_lusaka(%DateTime{} = dt), do: DateTime.add(dt, @lusaka_offset_seconds, :second)
end
