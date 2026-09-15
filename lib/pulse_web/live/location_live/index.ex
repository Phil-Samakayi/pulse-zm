defmodule PulseWeb.LocationLive.Index do
  @moduledoc """
  The locations list — the Elixir/LiveView equivalent of the React
  `LocationsPage.jsx`. Grouped by location type (residential areas vs
  markets) the same way the original did.
  """

  use PulseWeb, :live_view

  alias Pulse.Reports
  alias Pulse.Reports.Location

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        Pulse — Zambia cost-of-living tracker
        <:subtitle>
          Crowdsourced power/water outage and market price reports for Lusaka. Pick a
          location to see its latest reports, or add one yourself.
        </:subtitle>
      </.header>

      <div :if={@grouped == %{}} class="mt-8 text-ink-soft">
        No locations yet.
      </div>

      <div :for={type <- Location.location_types()} :if={@grouped[type]} class="mt-8">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-ink-soft">
          {group_label(type)}
        </h2>

        <ul class="mt-2 divide-y divide-line rounded-lg border border-line">
          <li :for={location <- @grouped[type]}>
            <.link
              navigate={~p"/locations/#{location.id}"}
              class="flex items-center justify-between px-4 py-3 hover:bg-paper-raised"
            >
              <span class="font-medium">{location.name}</span>
              <span class="text-sm text-ink-soft">{location.city}</span>
            </.link>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    grouped = Reports.list_locations() |> Enum.group_by(& &1.location_type)

    {:ok, assign(socket, grouped: grouped, page_title: "Locations")}
  end

  defp group_label("residential"), do: "Residential areas"
  defp group_label("market"), do: "Markets"
  defp group_label(other), do: other
end
