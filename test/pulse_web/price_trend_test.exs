defmodule PulseWeb.PriceTrendTest do
  use ExUnit.Case, async: true

  alias PulseWeb.PriceTrend

  # Thursday 5 Nov, 10:00 in Lusaka; this week started Monday 2 Nov.
  @now ~U[2026-11-05 08:00:00Z]

  defp report(price, at, place),
    do: %{price_kwacha: Decimal.new(price), reported_at: at, location: %{name: place}}

  test "the chart starts at Lusaka midnight on the Monday seven weeks back" do
    assert PriceTrend.window_start(@now) == ~U[2026-09-13 22:00:00Z]
  end

  test "weekly/2 keeps the cheapest price of each Lusaka week" do
    reports = [
      report("310.00", ~U[2026-09-15 08:00:00Z], "Chilenje Market"),
      report("305.00", ~U[2026-09-16 08:00:00Z], "City Market"),
      # 00:30 on Monday 2 Nov in Lusaka, though still 1 Nov in UTC.
      report("299.00", ~U[2026-11-01 22:30:00Z], "City Market"),
      report("295.00", ~U[2026-11-03 08:00:00Z], "Soweto Market")
    ]

    weekly = PriceTrend.weekly(reports, @now)

    assert length(weekly) == 8
    assert hd(weekly).cheapest.location.name == "City Market"
    assert List.last(weekly).cheapest.location.name == "Soweto Market"
    assert Enum.count(weekly, & &1.cheapest) == 2
  end

  test "chart/2 needs prices from at least two weeks" do
    one_week = PriceTrend.weekly([report("310.00", ~U[2026-11-03 08:00:00Z], "City Market")], @now)
    assert PriceTrend.chart(one_week, @now) == nil
  end

  test "chart/2 sums up the change and labels each point" do
    weekly =
      PriceTrend.weekly(
        [
          report("305.00", ~U[2026-09-16 08:00:00Z], "City Market"),
          report("295.00", ~U[2026-11-03 08:00:00Z], "Soweto Market")
        ],
        @now
      )

    chart = PriceTrend.chart(weekly, @now)

    assert chart.summary == "This week: K295.00 at Soweto Market · down K10.00 since week of 14 Sep"
    assert Enum.map(chart.dots, & &1.tip) == ["Week of 14 Sep: K305.00 at City Market", "This week: K295.00 at Soweto Market"]
    assert [%{latest: false}, %{latest: true}] = chart.dots
    assert Enum.map(chart.y_labels, & &1.text) == ["K305", "K295"]
  end
end
