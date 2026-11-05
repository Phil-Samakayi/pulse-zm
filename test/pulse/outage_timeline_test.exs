defmodule Pulse.OutageTimelineTest do
  use Pulse.DataCase, async: true

  import Pulse.ReportsFixtures

  alias Pulse.Reports
  alias Pulse.Reports.OutageReport

  defp hours_ago(n),
    do: DateTime.utc_now() |> DateTime.add(-round(n * 3600), :second) |> DateTime.truncate(:second)

  defp insert!(location, utility, status, hours_ago, opts \\ []) do
    %OutageReport{
      location_id: location.id,
      utility: utility,
      status: status,
      reported_at: hours_ago(hours_ago),
      is_flagged: Keyword.get(opts, :flagged, false)
    }
    |> Repo.insert!()
  end

  test "gives a timeline per utility that has reports this week" do
    location = location_fixture()
    insert!(location, "electricity", "down", 10)
    insert!(location, "electricity", "up", 4)

    timelines = Reports.outage_timeline(location.id, hours_ago(24), DateTime.utc_now())

    assert Map.keys(timelines) == ["electricity"]
    assert_in_delta timelines["electricity"].out_seconds, 6 * 3600, 5
  end

  test "leaves out flagged reports and other places" do
    location = location_fixture()
    insert!(location, "water", "down", 3, flagged: true)
    insert!(location_fixture(), "water", "down", 3)

    assert Reports.outage_timeline(location.id, hours_ago(24), DateTime.utc_now()) == %{}
  end
end
