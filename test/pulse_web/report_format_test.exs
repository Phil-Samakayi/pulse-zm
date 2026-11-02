defmodule PulseWeb.ReportFormatTest do
  use ExUnit.Case, async: true

  alias PulseWeb.ReportFormat
  alias Pulse.Reports.OutageReport

  # 10:00 in Lusaka (UTC+2).
  @now ~U[2026-11-02 08:00:00Z]

  describe "reported_when/2 (Lusaka time)" do
    test "recent reports are relative" do
      assert ReportFormat.reported_when(~U[2026-11-02 07:59:30Z], @now) == "just now"
      assert ReportFormat.reported_when(~U[2026-11-02 07:48:00Z], @now) == "12 min ago"
    end

    test "earlier today and yesterday use the local clock time" do
      # 04:46 UTC is 06:46 in Lusaka.
      assert ReportFormat.reported_when(~U[2026-11-02 04:46:00Z], @now) == "today, 06:46"
      assert ReportFormat.reported_when(~U[2026-11-01 16:20:00Z], @now) == "yesterday, 18:20"
    end

    test "the local date decides 'today', not the UTC date" do
      # 23:30 UTC on 1 Nov is already 01:30 on 2 Nov in Lusaka.
      assert ReportFormat.reported_when(~U[2026-11-01 23:30:00Z], @now) == "today, 01:30"
    end

    test "older reports show the date, with the year only if it differs" do
      assert ReportFormat.reported_when(~U[2026-10-01 04:46:00Z], @now) == "1 Oct, 06:46"
      assert ReportFormat.reported_when(~U[2025-10-01 04:46:00Z], @now) == "1 Oct 2025, 06:46"
    end
  end

  test "full_time/1 is in Lusaka time" do
    assert ReportFormat.full_time(~U[2026-10-01 04:46:00Z]) == "1 Oct 2026, 06:46 (Lusaka time)"
  end

  test "time_ago/2 stays compact" do
    assert ReportFormat.time_ago(~U[2026-11-02 05:00:00Z], @now) == "3 h ago"
    assert ReportFormat.time_ago(~U[2026-10-01 04:46:00Z], @now) == "1 Oct"
  end

  test "status_class/2 mutes reports older than a day" do
    fresh = %OutageReport{status: "down", reported_at: ~U[2026-11-02 07:00:00Z]}
    old = %OutageReport{status: "down", reported_at: ~U[2026-10-30 07:00:00Z]}

    assert ReportFormat.status_class(fresh, @now) == "text-danger"
    assert ReportFormat.status_class(old, @now) == "text-ink-soft"
  end

  test "outage_short/1 uses the same words as the home page" do
    assert ReportFormat.outage_short(%OutageReport{utility: "electricity", status: "down"}) ==
             "Power out"

    assert ReportFormat.outage_short(%OutageReport{utility: "water", status: "up"}) == "Water on"
  end
end
