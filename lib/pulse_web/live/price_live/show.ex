defmodule PulseWeb.PriceLive.Show do
  @moduledoc """
  One item's price comparison (`/prices/:commodity`): every place's
  latest price from the last two weeks, cheapest first, with how much
  more each one costs than the cheapest, and a WhatsApp share of the
  whole list. Data from `Pulse.Reports.price_board/1`.

  Below the list, the cheapest price each week over the last eight weeks
  as a line (`PulseWeb.PriceTrend`, from `Pulse.Reports.price_history/2`).
  Tapping a week shows its price and market in the line above the chart;
  that's plain JS in assets/js/app.js.

  Display only, like `PulseWeb.PriceLive.Index`, so it works without the
  live connection.
  """

  use PulseWeb, :live_view

  import PulseWeb.ReportFormat,
    only: [
      item_with_unit: 1,
      kwacha: 1,
      reported_when: 2,
      reporter_name: 1,
      full_time: 1,
      price_share_text: 4,
      whatsapp_url: 1
    ]

  alias Pulse.Reports
  alias Pulse.Reports.PriceReport
  alias PulseWeb.PriceTrend

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.link
        navigate={~p"/prices"}
        class="text-sm font-semibold leading-6 text-copper-strong hover:text-copper"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> Compare prices
      </.link>

      <.header class="mt-4">
        {item_with_unit(@commodity)}
        <:subtitle>Latest price at each place from the last two weeks, cheapest first.</:subtitle>
        <:actions>
          <.link
            href={whatsapp_url(price_share_text(@commodity, @reports, @url, @now))}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1.5 rounded-full border border-line px-3 py-1.5 text-sm font-semibold text-ink hover:border-copper hover:text-copper-strong"
          >
            <.icon name="hero-share-mini" class="h-4 w-4" />
            <span><span class="hidden sm:inline">Share on </span>WhatsApp</span>
          </.link>
        </:actions>
      </.header>

      <div
        :if={@reports == []}
        class="mt-8 rounded-lg border border-dashed border-line bg-paper-raised px-4 py-6 text-center"
      >
        <PulseWeb.Illustrations.basket class="mx-auto h-16 w-16 text-copper" />
        <p class="mt-2 font-semibold text-ink">No prices in the last two weeks yet</p>
        <p class="mt-1 text-sm text-ink-soft">
          Seen one? Open the market from the
          <.link href={~p"/" <> "#group-market"} class="font-semibold text-copper-strong hover:underline">
            locations list
          </.link>
          and tap “Report a price”.
        </p>
      </div>

      <ul :if={@reports != []} class="mt-8 divide-y divide-line rounded-lg border border-line">
        <li :for={report <- @reports} class="flex items-start justify-between gap-4 px-4 py-3">
          <div class="min-w-0">
            <.link
              navigate={~p"/locations/#{report.location.id}"}
              class="font-medium text-ink hover:text-copper-strong hover:underline"
            >
              {report.location.name}
            </.link>
            <p class="mt-1 text-xs text-ink-soft" title={full_time(report.reported_at)}>
              {reporter_name(report)} · {reported_when(report.reported_at, @now)}
            </p>
            <p :if={report.note != ""} class="mt-1 text-sm text-ink">{report.note}</p>
          </div>

          <div class="shrink-0 text-right">
            <p class={["font-semibold", report == hd(@reports) && "text-teal"]}>
              {kwacha(report.price_kwacha)}
            </p>
            <p
              :if={report == hd(@reports) and length(@reports) > 1}
              class="text-xs font-semibold text-teal"
            >
              Cheapest
            </p>
            <p :if={report != hd(@reports)} class="text-xs text-ink-soft">
              +{kwacha(Decimal.sub(report.price_kwacha, hd(@reports).price_kwacha))}
            </p>
          </div>
        </li>
      </ul>

      <section
        class="mt-6 rounded-lg border border-line bg-paper-raised p-4"
        aria-label="Price trend"
        data-trend
      >
        <p class="font-semibold text-ink">Cheapest each week</p>
        <p class="text-xs text-ink-soft">Last {PriceTrend.weeks()} weeks</p>

        <p :if={!@trend} class="mt-3 text-sm text-ink-soft">
          Not enough prices yet for a trend. The line appears once there are prices from two
          different weeks.
        </p>

        <div :if={@trend}>
          <p data-trend-readout class="mt-2 min-h-[1.25rem] text-sm text-ink">{@trend.summary}</p>
          <svg
            viewBox={"0 0 #{@trend.width} #{@trend.height}"}
            class="mt-2 block h-auto w-full overflow-visible"
            role="img"
            aria-label={@trend.summary}
          >
            <g :for={label <- @trend.y_labels}>
              <line
                x1={@trend.left}
                x2={@trend.right}
                y1={label.y}
                y2={label.y}
                class="stroke-line"
                stroke-dasharray="3 3"
              />
              <text x={@trend.left - 6} y={label.y + 3} text-anchor="end" font-size="9" class="fill-ink-soft">
                {label.text}
              </text>
            </g>
            <text
              :for={label <- @trend.x_labels}
              x={label.x}
              y={@trend.height - 6}
              text-anchor={label.anchor}
              font-size="9"
              class="fill-ink-soft"
            >
              {label.text}
            </text>
            <polyline
              points={@trend.line}
              fill="none"
              class="stroke-teal"
              stroke-width="2.5"
              stroke-linejoin="round"
              stroke-linecap="round"
            />
            <g :for={dot <- @trend.dots}>
              <circle
                cx={dot.x}
                cy={dot.y}
                r={if dot.latest, do: 5, else: 3.5}
                class={["stroke-teal", if(dot.latest, do: "fill-teal", else: "fill-paper-raised")]}
                stroke-width="2"
              />
              <%!-- A wide, invisible tap target over each week's point. --%>
              <rect
                x={dot.x - 16}
                y={@trend.plot_top}
                width="32"
                height={@trend.plot_height}
                fill="transparent"
                class="cursor-pointer"
                data-trend-tip={dot.tip}
              />
            </g>
          </svg>
        </div>
      </section>
    </div>
    """
  end

  def mount(%{"commodity" => commodity}, _session, socket) do
    if commodity in PriceReport.comparable_commodities() do
      if connected?(socket) do
        Enum.each(Reports.list_locations(), &Reports.subscribe(&1.id))
        :timer.send_interval(:timer.minutes(1), :tick)
      end

      {:ok,
       socket
       |> assign(
         commodity: commodity,
         page_title: "#{item_with_unit(commodity)} prices",
         url: url(~p"/prices/#{commodity}")
       )
       |> assign_reports()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Pulse doesn't compare prices for that item.")
       |> push_navigate(to: ~p"/prices")}
    end
  end

  def handle_info({:report_created, _report}, socket), do: {:noreply, assign_reports(socket)}
  def handle_info(:tick, socket), do: {:noreply, assign(socket, now: DateTime.utc_now())}

  defp assign_reports(socket) do
    commodity = socket.assigns.commodity
    now = DateTime.utc_now()
    reports = Map.get(Reports.price_board(), commodity, [])

    trend =
      commodity
      |> Reports.price_history(PriceTrend.window_start(now))
      |> PriceTrend.weekly(now)
      |> PriceTrend.chart(now)

    assign(socket, reports: reports, trend: trend, now: now)
  end
end
