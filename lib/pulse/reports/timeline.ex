defmodule Pulse.Reports.Timeline do
  @moduledoc """
  Turns one utility's outage reports at one place into a timeline of
  stretches (out, on, or unknown), for the week-of-outages strip on the
  location page. See `Pulse.Reports.outage_timeline/3`.

  The rule:

    * A report's status holds until the next report, so "out at 18:20,
      on at 06:10" is out from 18:20 to 06:10.
    * It holds for at most 12 hours, though. After
      that nobody has said anything, so the stretch is unknown rather than
      guessed. A "me too" (the same status again) restarts that clock.
    * Back-to-back stretches with the same status are merged, so a run of
      "me too" reports is one stretch.

  Pure functions only: the caller fetches the reports.
  """

  @hold_seconds 12 * 60 * 60

  @doc "How long a report's status is assumed to hold with no newer report."
  def hold_seconds, do: @hold_seconds

  @doc """
  Builds the timeline from `window_start` to `now`.

  `reports` are maps or structs with `:status` ("up"/"down") and
  `:reported_at`, in any order; include any from up to `hold_seconds/0`
  before `window_start`, so a status that was already holding when the
  window opened carries into it.

  Returns `%{segments: [...], out_seconds: n, known?: boolean}`, where each
  segment is `%{status: "up" | "down" | :unknown, from: dt, to: dt}`,
  covering the window end to end in order. `known?` is false when nothing
  in the window is known, so the caller can leave that utility out.
  """
  def build(reports, %DateTime{} = window_start, %DateTime{} = now) do
    known =
      reports
      |> Enum.sort_by(& &1.reported_at, DateTime)
      |> Enum.chunk_every(2, 1)
      |> Enum.map(&stretch(&1, now))
      |> Enum.map(fn seg -> %{seg | from: latest(seg.from, window_start), to: earliest(seg.to, now)} end)
      |> Enum.filter(&(DateTime.compare(&1.from, &1.to) == :lt))
      |> merge()

    segments = fill_gaps(known, window_start, now)

    %{
      segments: segments,
      out_seconds:
        segments
        |> Enum.filter(&(&1.status == "down"))
        |> Enum.map(&DateTime.diff(&1.to, &1.from))
        |> Enum.sum(),
      known?: known != []
    }
  end

  # A report holds until the next one, or for @hold_seconds, whichever is
  # sooner. The last report can't hold past now.
  defp stretch([report, next], _now),
    do: %{status: report.status, from: report.reported_at, to: earliest(next.reported_at, held_until(report))}

  defp stretch([report], now),
    do: %{status: report.status, from: report.reported_at, to: earliest(now, held_until(report))}

  defp held_until(report), do: DateTime.add(report.reported_at, @hold_seconds, :second)

  defp merge(segments) do
    segments
    |> Enum.reduce([], fn
      seg, [prev | rest] = acc ->
        if prev.status == seg.status and DateTime.compare(prev.to, seg.from) == :eq,
          do: [%{prev | to: seg.to} | rest],
          else: [seg | acc]

      seg, [] ->
        [seg]
    end)
    |> Enum.reverse()
  end

  defp fill_gaps(known, window_start, now) do
    {segments, cursor} =
      Enum.reduce(known, {[], window_start}, fn seg, {acc, cursor} ->
        acc = if DateTime.compare(cursor, seg.from) == :lt, do: [unknown(cursor, seg.from) | acc], else: acc
        {[seg | acc], seg.to}
      end)

    segments =
      if DateTime.compare(cursor, now) == :lt, do: [unknown(cursor, now) | segments], else: segments

    Enum.reverse(segments)
  end

  defp unknown(from, to), do: %{status: :unknown, from: from, to: to}

  defp earliest(a, b), do: if(DateTime.compare(a, b) == :gt, do: b, else: a)
  defp latest(a, b), do: if(DateTime.compare(a, b) == :lt, do: b, else: a)
end
