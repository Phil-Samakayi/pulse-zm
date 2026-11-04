defmodule PulseWeb.PriceLive.Show do
  @moduledoc """
  One item's price comparison (`/prices/:commodity`): every place's
  latest price from the last two weeks, cheapest first, with how much
  more each one costs than the cheapest, and a WhatsApp share of the
  whole list. Data from `Pulse.Reports.price_board/1`.

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

      <p :if={@reports == []} class="mt-8 text-sm text-ink-soft">
        No prices in the last two weeks yet. Seen one? Open the market from the
        <.link navigate={~p"/"} class="font-semibold text-copper-strong hover:underline">
          locations list
        </.link>
        and tap “Report a price”.
      </p>

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
    reports = Map.get(Reports.price_board(), socket.assigns.commodity, [])
    assign(socket, reports: reports, now: DateTime.utc_now())
  end
end
