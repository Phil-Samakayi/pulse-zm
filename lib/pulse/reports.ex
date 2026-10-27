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

  # Anti-spam rate limits, enforced per logged-in user via Pulse.RateLimit
  # (Hammer, ETS backend — see that module's moduledoc on scope/limits).
  # These catch a scripted/automated flood of submissions; the duplicate
  # cooldown below catches accidental or lazy double-submits of the exact
  # same report and stays separate from this.
  @report_rate_limit 5
  @report_rate_scale :timer.minutes(1)
  @location_rate_limit 3
  @location_rate_scale :timer.hours(1)

  ## Locations

  @doc "Public listing — approved locations only. Pending/rejected ones never show up here."
  def list_locations do
    Repo.all(
      from l in Location,
        where: l.status == ^Location.approved(),
        order_by: [asc: l.city, asc: l.name]
    )
  end

  def get_location!(id), do: Repo.get!(Location, id)

  @doc "Admin/seed path — inserts a pre-approved location directly. Used by seeds.exs."
  def create_location(attrs) do
    %Location{} |> Location.changeset(attrs) |> Repo.insert()
  end

  @doc "For a `phx-change=\"validate\"` handler on the admin changeset — no insert attempted."
  def change_location(%Location{} = location \\ %Location{}, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  @doc """
  A regular user proposing a new location. Always lands with status
  "pending". Rate-limited per user — proposing locations is rarer and
  more disruptive to the moderation queue than an outage/price report,
  so it gets its own, stricter limit.
  """
  def submit_location(attrs) do
    user_id = attrs["submitted_by_id"] || attrs[:submitted_by_id]

    with :ok <- check_location_rate(%Location{}, attrs, user_id) do
      %Location{} |> Location.submission_changeset(attrs) |> Repo.insert()
    end
  end

  @doc "For the submission form's `phx-change=\"validate\"` handler — no insert attempted."
  def change_location_submission(%Location{} = location \\ %Location{}, attrs \\ %{}) do
    Location.submission_changeset(location, attrs)
  end

  @doc "The moderation queue's list of locations awaiting review, oldest first."
  def list_pending_locations do
    Repo.all(
      from l in Location,
        where: l.status == ^Location.pending(),
        order_by: [asc: l.inserted_at],
        preload: [:submitted_by]
    )
  end

  def approve_location(%Location{} = location) do
    location
    |> Location.review_changeset(%{"status" => Location.approved()})
    |> Repo.update()
  end

  def reject_location(%Location{} = location, reason) do
    location
    |> Location.review_changeset(%{"status" => Location.rejected(), "rejection_note" => reason})
    |> Repo.update()
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

  @doc """
  What the locations list shows on each row, for every location in
  `location_ids` at once: the latest outage report per utility, and when
  prices were last reported there. Two queries in total, however many
  locations there are — not two per location.

  Returns `%{location_id => %{outages: [%OutageReport{}], prices_updated_at: DateTime.t() | nil}}`,
  with outages in `OutageReport.utilities/0` order (electricity, then
  water). A location with no reports of either kind is left out of the
  map entirely.

  The outage query uses Postgres `DISTINCT ON (location_id, utility)`.
  Ecto puts the distinct columns first in the ORDER BY, so
  `desc: reported_at` keeps the newest row of each group — the same
  answer `latest_per(:outage, ...)` gives for a single location, and
  covered by the existing `[:location_id, :utility, :reported_at]` index.
  """
  def location_summaries(location_ids) when is_list(location_ids) do
    outages =
      Repo.all(
        from r in OutageReport,
          where: r.location_id in ^location_ids,
          distinct: [r.location_id, r.utility],
          order_by: [desc: r.reported_at]
      )
      |> Enum.group_by(& &1.location_id)

    prices_updated_at =
      Repo.all(
        from r in PriceReport,
          where: r.location_id in ^location_ids,
          group_by: r.location_id,
          select: {r.location_id, max(r.reported_at)}
      )
      |> Map.new()

    (Map.keys(outages) ++ Map.keys(prices_updated_at))
    |> Enum.uniq()
    |> Map.new(fn location_id ->
      {location_id,
       %{
         outages: outages |> Map.get(location_id, []) |> Enum.sort_by(&utility_position/1),
         prices_updated_at: Map.get(prices_updated_at, location_id)
       }}
    end)
  end

  defp utility_position(%OutageReport{utility: utility}) do
    Enum.find_index(OutageReport.utilities(), &(&1 == utility))
  end

  ## Outage reports

  def create_outage_report(attrs) do
    user_id = attrs["reported_by_id"] || attrs[:reported_by_id]

    with :ok <- check_report_rate(%OutageReport{}, attrs, user_id),
         :ok <- check_outage_cooldown(attrs) do
      %OutageReport{}
      |> OutageReport.changeset(attrs)
      |> Repo.insert()
      |> broadcast_on_success(attrs["location_id"] || attrs[:location_id])
    end
  end

  @doc """
  A changeset for live validation as the user types, before they submit —
  used by `LocationLive.Show`'s `phx-change="validate_outage"`. Doesn't
  check the duplicate-report cooldown or the rate limit; those are only
  checked on submit, since both depend on exactly when the submit happens.
  """
  def change_outage_report(attrs \\ %{}) do
    OutageReport.changeset(%OutageReport{}, attrs)
  end

  defp check_outage_cooldown(attrs) do
    user_id = attrs["reported_by_id"] || attrs[:reported_by_id]
    location_id = attrs["location_id"] || attrs[:location_id]
    utility = attrs["utility"] || attrs[:utility]

    if user_id && location_id && utility && recent_outage_exists?(user_id, location_id, utility) do
      {:error,
       base_error_changeset(
         %OutageReport{},
         attrs,
         "You already reported this at this location in the last #{@duplicate_cooldown_minutes} minutes — please wait before submitting again."
       )}
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
    user_id = attrs["reported_by_id"] || attrs[:reported_by_id]

    with :ok <- check_report_rate(%PriceReport{}, attrs, user_id),
         :ok <- check_price_cooldown(attrs) do
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
      {:error,
       base_error_changeset(
         %PriceReport{},
         attrs,
         "You already reported this at this location in the last #{@duplicate_cooldown_minutes} minutes — please wait before submitting again."
       )}
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

  ## Rate limiting — see Pulse.RateLimit's moduledoc for the Hammer setup
  ## this calls into. Checked only on submit (not on live validation), the
  ## same way the duplicate cooldown is.

  defp check_report_rate(struct, attrs, user_id) do
    check_rate(struct, attrs, "report:#{user_id}", @report_rate_scale, @report_rate_limit)
  end

  defp check_location_rate(struct, attrs, user_id) do
    check_rate(struct, attrs, "location:#{user_id}", @location_rate_scale, @location_rate_limit)
  end

  defp check_rate(struct, attrs, key, scale, limit) do
    case Pulse.RateLimit.hit(key, scale, limit) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        wait_seconds = retry_after_ms |> div(1000) |> max(1)

        {:error,
         base_error_changeset(
           struct,
           attrs,
           "You're submitting too quickly — try again in #{wait_seconds}s."
         )}
    end
  end

  defp base_error_changeset(struct, attrs, message) do
    struct
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.cast(attrs, [])
    |> Ecto.Changeset.add_error(:base, message)
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
