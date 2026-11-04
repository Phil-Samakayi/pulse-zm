defmodule PulseWeb.ReportFormatTest do
  use ExUnit.Case, async: true

  alias PulseWeb.ReportFormat
  alias Pulse.Reports.{Location, OutageReport, PriceReport}

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

  describe "share_text/6" do
    test "lists each status and price, then the link" do
      location = %Location{name: "Kabwata"}
      power = %OutageReport{utility: "electricity", status: "down", reported_at: ~U[2026-11-02 07:30:00Z]}
      water = %OutageReport{utility: "water", status: "up", reported_at: ~U[2026-11-01 16:20:00Z]}

      runs = %{
        "electricity" => %{people: 14, since: ~U[2026-11-02 04:46:00Z]},
        "water" => %{people: 1, since: ~U[2026-11-01 16:20:00Z]}
      }

      price = %PriceReport{
        commodity: "mealie_meal",
        commodity_other: "",
        unit: "25kg bag",
        price_kwacha: Decimal.new("450.00"),
        reported_at: ~U[2026-10-01 07:10:00Z]
      }

      text =
        ReportFormat.share_text(location, [power, water], runs, [price], "https://x.test/locations/1", @now)

      assert text ==
               Enum.join(
                 [
                   "*Kabwata* on Pulse",
                   "• Power out since today, 06:46 · 14 people",
                   "• Water on · yesterday, 18:20",
                   "• Mealie meal: K450.00 / 25kg bag · 1 Oct, 09:10",
                   "https://x.test/locations/1"
                 ],
                 "\n"
               )
    end

    test "says so when there are no reports yet" do
      text = ReportFormat.share_text(%Location{name: "Chawama"}, [], %{}, [], "https://x.test", @now)
      assert text == "*Chawama* on Pulse\nNo reports yet. Add one:\nhttps://x.test"
    end
  end

  describe "price_share_text/4" do
    test "lists each market's price, cheapest first, then the link" do
      reports = [
        %PriceReport{
          price_kwacha: Decimal.new("420.00"),
          reported_at: ~U[2026-11-02 07:10:00Z],
          location: %Location{name: "City Market"}
        },
        %PriceReport{
          price_kwacha: Decimal.new("450.00"),
          reported_at: ~U[2026-11-01 14:30:00Z],
          location: %Location{name: "Soweto Market"}
        }
      ]

      text = ReportFormat.price_share_text("mealie_meal", reports, "https://x.test/prices/mealie_meal", @now)

      assert text ==
               Enum.join(
                 [
                   "*Mealie meal (25kg bag)* prices on Pulse",
                   "• K420.00 at City Market · today, 09:10",
                   "• K450.00 at Soweto Market · yesterday, 16:30",
                   "https://x.test/prices/mealie_meal"
                 ],
                 "\n"
               )
    end

    test "says so when there are no recent prices" do
      assert ReportFormat.price_share_text("onions", [], "https://x.test", @now) ==
               "*Onions (pile)* prices on Pulse\nNo prices reported in the last two weeks. Add one:\nhttps://x.test"
    end
  end

  test "item_with_unit/1 and kwacha/1" do
    assert ReportFormat.item_with_unit("cooking_oil") == "Cooking oil (2.5 litres)"
    assert ReportFormat.item_with_unit("other") == "Other"
    assert ReportFormat.kwacha(Decimal.new("126.00")) == "K126.00"
  end

  test "whatsapp_url/1 percent-encodes the message" do
    assert ReportFormat.whatsapp_url("a b\n*c*") == "https://wa.me/?text=a%20b%0A%2Ac%2A"
  end

  test "people/1" do
    assert ReportFormat.people(1) == "1 person"
    assert ReportFormat.people(14) == "14 people"
  end

  test "outage_short/1 uses the same words as the home page" do
    assert ReportFormat.outage_short(%OutageReport{utility: "electricity", status: "down"}) ==
             "Power out"

    assert ReportFormat.outage_short(%OutageReport{utility: "water", status: "up"}) == "Water on"
  end
end
