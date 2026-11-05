defmodule Pulse.Reports.TimelineTest do
  use ExUnit.Case, async: true

  alias Pulse.Reports.Timeline

  @t0 ~U[2026-11-02 10:00:00Z]

  defp hours(n), do: DateTime.add(@t0, round(n * 3600), :second)
  defp report(status, at), do: %{status: status, reported_at: at}

  defp shape(%{segments: segments}),
    do: Enum.map(segments, &{&1.status, DateTime.diff(&1.to, &1.from) / 3600})

  test "a status holds until the next report" do
    timeline = Timeline.build([report("down", @t0), report("up", hours(5))], hours(-1), hours(8))

    assert shape(timeline) == [{:unknown, 1.0}, {"down", 5.0}, {"up", 3.0}]
    assert timeline.out_seconds == 5 * 3600
    assert timeline.known?
  end

  test "it holds for 12 hours at most, then nobody knows" do
    timeline = Timeline.build([report("down", @t0)], @t0, hours(20))

    assert shape(timeline) == [{"down", 12.0}, {:unknown, 8.0}]
  end

  test "me-too reports join into one stretch" do
    timeline = Timeline.build([report("down", @t0), report("down", hours(2))], @t0, hours(4))

    assert shape(timeline) == [{"down", 4.0}]
  end

  test "a status from just before the window carries into it" do
    timeline = Timeline.build([report("down", hours(-2))], @t0, hours(3))

    assert shape(timeline) == [{"down", 3.0}]
  end

  test "reports too old to count leave nothing known" do
    timeline = Timeline.build([report("up", hours(-20))], @t0, hours(3))

    assert shape(timeline) == [{:unknown, 3.0}]
    refute timeline.known?
  end
end
