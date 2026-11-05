defmodule PulseWeb.PriceTrend do
  @moduledoc """
  The price trend line on an item's price page (`PulseWeb.PriceLive.Show`):
  the cheapest reported price each week over the last eight weeks.

  Weeks run Monday to Sunday in Lusaka time. `weekly/2` buckets the
  reports from `Pulse.Reports.price_history/2` into weeks, and `chart/2`
  turns those into the numbers the SVG needs (point positions, axis
  labels, the line under the chart). Pure functions, so they're tested
  without a database or a browser.
  """

  import PulseWeb.ReportFormat, only: [kwacha: 1, lusaka_date: 1]

  @weeks 8

  # The SVG's coordinate box, and the room left for the axis labels.
  @width 300
  @height 130
  @left 38
  @right 10
  @top 10
  @bottom 22

  def weeks, do: @weeks

  @doc "Where the chart starts: Monday 00:00 (Lusaka) seven weeks before this one, in UTC."
  def window_start(%DateTime{} = now) do
    now
    |> first_monday()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.add(-2 * 60 * 60, :second)
  end

  @doc """
  One entry per week, oldest first: `%{week: monday, cheapest: report | nil}`.
  The cheapest report of each week (the latest one on a tie), or nil for a
  week with no prices. Reports need `:price_kwacha` and `:reported_at`.
  """
  def weekly(reports, %DateTime{} = now) do
    by_week = Enum.group_by(reports, &monday(lusaka_date(&1.reported_at)))

    for week <- mondays(now) do
      cheapest =
        case by_week[week] do
          nil -> nil
          reports -> Enum.min_by(reports, &{Decimal.to_float(&1.price_kwacha), -DateTime.to_unix(&1.reported_at)})
        end

      %{week: week, cheapest: cheapest}
    end
  end

  @doc """
  What the SVG needs, or nil when fewer than two weeks have a price (a
  single point isn't a trend). Reports need `:location` with a `:name`.
  """
  def chart(weekly, %DateTime{} = now) do
    present =
      weekly
      |> Enum.with_index()
      |> Enum.filter(fn {%{cheapest: cheapest}, _i} -> cheapest end)

    if length(present) < 2 do
      nil
    else
      prices = Enum.map(present, fn {%{cheapest: r}, _} -> Decimal.to_float(r.price_kwacha) end)
      {lo, hi} = {Enum.min(prices), Enum.max(prices)}
      {y_lo, y_hi} = padded(lo, hi)
      y = fn price -> round1(@top + (y_hi - price) / (y_hi - y_lo) * (@height - @top - @bottom)) end
      this_week = monday(lusaka_date(now))

      dots =
        Enum.map(present, fn {%{week: week, cheapest: r}, i} ->
          %{
            x: x(i),
            y: y.(Decimal.to_float(r.price_kwacha)),
            tip: "#{week_label(week, this_week)}: #{kwacha(r.price_kwacha)} at #{r.location.name}"
          }
        end)

      dots = List.update_at(dots, -1, &Map.put(&1, :latest, true))

      %{
        width: @width,
        height: @height,
        left: @left,
        right: @width - @right,
        plot_top: @top,
        plot_height: @height - @top - @bottom,
        line: Enum.map_join(dots, " ", &"#{&1.x},#{&1.y}"),
        dots: Enum.map(dots, &Map.put_new(&1, :latest, false)),
        y_labels: Enum.uniq([%{y: y.(hi), text: whole_kwacha(hi)}, %{y: y.(lo), text: whole_kwacha(lo)}]),
        x_labels: x_labels(weekly, this_week),
        summary: summary(present, this_week)
      }
    end
  end

  # "This week: K295.00 at Soweto Market · down K15.00 since week of 8 Sep"
  defp summary(present, this_week) do
    {%{week: first_week, cheapest: first}, _} = hd(present)
    {%{week: last_week, cheapest: last}, _} = List.last(present)

    change =
      case Decimal.compare(last.price_kwacha, first.price_kwacha) do
        :lt -> "down #{kwacha(Decimal.sub(first.price_kwacha, last.price_kwacha))}"
        :gt -> "up #{kwacha(Decimal.sub(last.price_kwacha, first.price_kwacha))}"
        :eq -> "no change"
      end

    "#{week_label(last_week, this_week)}: #{kwacha(last.price_kwacha)} at #{last.location.name} · " <>
      "#{change} since week of #{short_date(first_week)}"
  end

  defp x_labels(weekly, this_week) do
    for {%{week: week}, i} <- Enum.with_index(weekly), rem(i, 2) == 1 do
      %{
        x: x(i),
        text: if(week == this_week, do: "This week", else: short_date(week)),
        # The last label sits at the right edge, so it ends there instead of centring.
        anchor: if(i == @weeks - 1, do: "end", else: "middle")
      }
    end
  end

  defp week_label(week, this_week) when week == this_week, do: "This week"
  defp week_label(week, _this_week), do: "Week of #{short_date(week)}"

  defp short_date(date), do: Calendar.strftime(date, "%-d %b")

  defp x(i), do: round1(@left + i * (@width - @left - @right) / (@weeks - 1))

  # Leave a little room above and below the line, and give a flat line
  # some height so it sits in the middle rather than on an edge.
  defp padded(lo, hi) when lo == hi, do: {lo - 10, hi + 10}
  defp padded(lo, hi), do: {lo - (hi - lo) * 0.15, hi + (hi - lo) * 0.15}

  defp whole_kwacha(price), do: "K#{round(price)}"

  defp round1(value), do: Float.round(value * 1.0, 1)

  defp mondays(now) do
    first = first_monday(now)
    for week <- 0..(@weeks - 1), do: Date.add(first, week * 7)
  end

  defp first_monday(now), do: now |> lusaka_date() |> monday() |> Date.add(-7 * (@weeks - 1))

  defp monday(date), do: Date.beginning_of_week(date, :monday)
end
