defmodule PulseWeb.PriceLive.Index do
  @moduledoc """
  "Compare prices": every standard item with its cheapest recent price
  and the range across places — the thing asking one person can't tell
  you. Each item links to `PulseWeb.PriceLive.Show`, which ranks every
  place for that item.

  Display only (prices are reported from a location's page), so it
  renders fully on the first HTTP load and works without the live
  connection; live updates and the once-a-minute "2 h ago" refresh are a
  bonus where the connection holds.
  """

  use PulseWeb, :live_view

  import PulseWeb.ReportFormat, only: [item_with_unit: 1, kwacha: 1, time_ago: 2, full_time: 1]

  alias Pulse.Reports
  alias Pulse.Reports.PriceReport

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.link
        navigate={~p"/"}
        class="text-sm font-semibold leading-6 text-copper-strong hover:text-copper"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> All locations
      </.link>

      <.header class="mt-4">
        Compare prices
        <:subtitle>
          The latest price at each place from the last two weeks, cheapest first. Open an
          item to see every place.
        </:subtitle>
      </.header>

      <ul :if={@priced != []} class="mt-8 divide-y divide-line rounded-lg border border-line">
        <li :for={commodity <- @priced}>
          <.link
            navigate={~p"/prices/#{commodity}"}
            class="group flex items-center justify-between gap-4 px-4 py-3 hover:bg-paper-raised"
          >
            <div class="min-w-0">
              <p class="font-medium">{item_with_unit(commodity)}</p>
              <.cheapest reports={@board[commodity]} now={@now} />
            </div>
            <.icon
              name="hero-chevron-right-mini"
              class="flex-none text-ink-soft transition group-hover:translate-x-0.5 group-hover:text-copper-strong"
            />
          </.link>
        </li>
      </ul>

      <div
        :if={@unpriced != []}
        class="mt-6 rounded-lg border border-dashed border-line bg-paper-raised px-4 py-6 text-center"
      >
        <PulseWeb.Illustrations.basket class="mx-auto h-16 w-16 text-copper" />
        <p class="mt-2 font-semibold text-ink">No prices in the last two weeks</p>
        <p class="mt-2 flex flex-wrap justify-center gap-1.5">
          <.link
            :for={commodity <- @unpriced}
            navigate={~p"/prices/#{commodity}"}
            class="rounded-full border border-line px-2.5 py-0.5 text-xs text-ink-soft hover:border-copper hover:text-copper-strong"
          >
            {item_with_unit(commodity)}
          </.link>
        </p>
        <p class="mt-4 text-sm text-ink-soft">Seen one at a market today? It takes 10 seconds.</p>
        <.link
          href={~p"/" <> "#group-market"}
          class="mt-3 inline-block rounded-full bg-copper-strong px-4 py-2 text-sm font-semibold text-paper-raised hover:bg-copper"
        >
          Report a price
        </.link>
        <p class="mt-2 text-xs text-ink-soft">Pick the market, then tap “Report a price” there.</p>
      </div>

      <p :if={@unpriced == []} class="mt-6 text-sm text-ink-soft">
        Seen a price? Open the market from the
        <.link navigate={~p"/"} class="font-semibold text-copper-strong hover:underline">
          locations list
        </.link>
        and tap “Report a price”.
      </p>
    </div>
    """
  end

  attr :reports, :list, required: true
  attr :now, DateTime, required: true

  defp cheapest(assigns) do
    assigns = assign(assigns, low: hd(assigns.reports), high: List.last(assigns.reports))

    ~H"""
    <p class="mt-0.5 text-sm text-ink-soft" title={full_time(@low.reported_at)}>
      <span :if={length(@reports) > 1}>Cheapest</span>
      <span class="font-semibold text-teal">{kwacha(@low.price_kwacha)}</span>
      at {@low.location.name} · {time_ago(@low.reported_at, @now)}
    </p>
    <p :if={length(@reports) > 1} class="text-sm text-ink-soft">
      {kwacha(@low.price_kwacha)}–{kwacha(@high.price_kwacha)} across {length(@reports)} places
    </p>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Enum.each(Reports.list_locations(), &Reports.subscribe(&1.id))
      :timer.send_interval(:timer.minutes(1), :tick)
    end

    {:ok, socket |> assign(page_title: "Compare prices") |> assign_board()}
  end

  # Broadcast by Pulse.Reports for new reports and flags at any location.
  def handle_info({:report_created, _report}, socket), do: {:noreply, assign_board(socket)}
  def handle_info(:tick, socket), do: {:noreply, assign(socket, now: DateTime.utc_now())}

  # Items with recent prices are listed first; the rest are folded into
  # one "No prices in the last two weeks" card with a way to help, rather
  # than a row each saying the same thing.
  defp assign_board(socket) do
    board = Reports.price_board()

    {priced, unpriced} =
      Enum.split_with(PriceReport.comparable_commodities(), &(Map.get(board, &1, []) != []))

    assign(socket, board: board, priced: priced, unpriced: unpriced, now: DateTime.utc_now())
  end
end
