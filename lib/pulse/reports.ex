defmodule Pulse.Reports do
  @moduledoc """
  The Reports context: locations, outage reports, price reports — plus the
  PubSub broadcasts that make the LiveViews update live for everyone
  looking at a location when someone else reports something there. That
  live-update is the main thing this Elixir rewrite buys over the original
  Django+React version, which had to poll or wait for a manual refresh.
  """

  import Ecto.Query, warn: false
  alias Pulse.Repo
  alias Pulse.Reports.{Location, OutageReport, PriceReport}

  @duplicate_cooldown_minutes 2

  ## Locations

  def list_locations do
    Repo.all(from l in Location, order_by: [asc: l.city, asc: l.name])
  end

  def get_location!(id), do: Repo.get!(Location, id)

  def create_location(attrs) do
    %Location{} |> Location.changeset(attrs) |> Repo.insert()
  end

  @doc "For a `phx-change=\"validate\"` handler — a changeset with no insert attempted."
  def change_location(%Location{} = location \\ %Location{}, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  @doc """
  The one call a "location page" needs: the location itself, its latest
  outage report per utility, and its latest price report per commodity.
  Mirrors the Django API's `/locations/<id>/status/` endpoint.
  """
  def location_status(%Location{} = location) do
    %{
      location: location,
      latest_outages: latest_per(:outage, location.id),
      latest_prices: latest_per(:price, location.id)
    }
  end

  defp latest_per(:outage, location_id) do
    OutageReport.utilities()
    |> Enum.map(fn utility ->
      Repo.one(
        from r in OutageReport,
          where: r.location_id == ^location_id and r.utility == ^utility,
          order_by: [desc: r.reported_at],
          limit: 1,
          preload: [:reported_by]
      )
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp latest_per(:price, location_id) do
    PriceReport.commodities()
    |> Enum.map(fn commodity ->
      Repo.one(
        from r in PriceReport,
          where: r.location_id == ^location_id and r.commodity == ^commodity,
          order_by: [desc: r.reported_at],
          limit: 1,
          preload: [:reported_by]
      )
    end)
    |> Enum.reject(&is_nil/1)
  end

  ## Outage reports

  def create_outage_report(attrs) do
    with :ok <- check_outage_cooldown(attrs) do
      %OutageReport{}
      |> OutageReport.changeset(attrs)
      |> Repo.insert()
      |> broadcast_on_success(attrs["location_id"] || attrs[:location_id])
    end
  end

  @doc """
  A changeset for live validation as the user types, before they submit —
  used by `LocationLive.Show`'s `phx-change="validate_outage"`. Doesn't
  check the duplicate-report cooldown; that's only checked on submit,
  since it depends on exactly when the submit happens.
  """
  def change_outage_report(attrs \\ %{}) do
    OutageReport.changeset(%OutageReport{}, attrs)
  end

  defp check_outage_cooldown(attrs) do
    user_id = attrs["reported_by_id"] || attrs[:reported_by_id]
    location_id = attrs["location_id"] || attrs[:location_id]
    utility = attrs["utility"] || attrs[:utility]

    if user_id && location_id && utility && recent_outage_exists?(user_id, location_id, utility) do
      {:error, cooldown_changeset(%OutageReport{}, attrs)}
    else
      :ok
    end
  end

  defp recent_outage_exists?(user_id, location_id, utility) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@duplicate_cooldown_minutes * 60, :second)

    Repo.exists?(
      from r in OutageReport,
        where:
          r.reported_by_id == ^user_id and r.location_id == ^location_id and
            r.utility == ^utility and r.reported_at >= ^cutoff
    )
  end

  def flag_outage_report(%OutageReport{} = report, attrs) do
    result =
      report
      |> OutageReport.flag_changeset(Map.put(attrs, "is_flagged", true))
      |> Repo.update()

    broadcast_on_success(result, report.location_id)
  end

  def clear_outage_flag(%OutageReport{} = report) do
    report
    |> OutageReport.flag_changeset(%{"is_flagged" => false, "flag_reason" => ""})
    |> Repo.update()
  end

  ## Price reports

  def create_price_report(attrs) do
    with :ok <- check_price_cooldown(attrs) do
      %PriceReport{}
      |> PriceReport.changeset(attrs)
      |> Repo.insert()
      |> broadcast_on_success(attrs["location_id"] || attrs[:location_id])
    end
  end

  @doc "Same idea as `change_outage_report/1`, for the price report form."
  def change_price_report(attrs \\ %{}) do
    PriceReport.changeset(%PriceReport{}, attrs)
  end

  defp check_price_cooldown(attrs) do
    user_id = attrs["reported_by_id"] || attrs[:reported_by_id]
    location_id = attrs["location_id"] || attrs[:location_id]
    commodity = attrs["commodity"] || attrs[:commodity]

    if user_id && location_id && commodity &&
         recent_price_exists?(user_id, location_id, commodity) do
      {:error, cooldown_changeset(%PriceReport{}, attrs)}
    else
      :ok
    end
  end

  defp recent_price_exists?(user_id, location_id, commodity) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@duplicate_cooldown_minutes * 60, :second)

    Repo.exists?(
      from r in PriceReport,
        where:
          r.reported_by_id == ^user_id and r.location_id == ^location_id and
            r.commodity == ^commodity and r.reported_at >= ^cutoff
    )
  end

  def flag_price_report(%PriceReport{} = report, attrs) do
    result =
      report
      |> PriceReport.flag_changeset(Map.put(attrs, "is_flagged", true))
      |> Repo.update()

    broadcast_on_success(result, report.location_id)
  end

  def clear_price_flag(%PriceReport{} = report) do
    report
    |> PriceReport.flag_changeset(%{"is_flagged" => false, "flag_reason" => ""})
    |> Repo.update()
  end

  defp cooldown_changeset(struct, attrs) do
    struct
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.cast(attrs, [])
    |> Ecto.Changeset.add_error(
      :base,
      "You already reported this at this location in the last #{@duplicate_cooldown_minutes} minutes — please wait before submitting again."
    )
    |> Map.put(:action, :insert)
  end

  ## Moderation

  def list_flagged_reports do
    %{
      outages: Repo.all(from r in OutageReport, where: r.is_flagged, preload: [:location, :reported_by]),
      prices: Repo.all(from r in PriceReport, where: r.is_flagged, preload: [:location, :reported_by])
    }
  end

  ## PubSub — this is what makes a second browser tab update live the
  ## moment someone reports something, with no polling or manual refresh.

  def subscribe(location_id) do
    Phoenix.PubSub.subscribe(Pulse.PubSub, topic(location_id))
  end

  defp topic(location_id), do: "location:#{location_id}"

  defp broadcast_on_success({:ok, report} = result, location_id) do
    Phoenix.PubSub.broadcast(Pulse.PubSub, topic(location_id), {:report_created, report})
    result
  end

  defp broadcast_on_success(result, _location_id), do: result
end
