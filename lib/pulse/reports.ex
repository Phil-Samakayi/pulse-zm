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
  alias Pulse.Reports.{Location, OutageReport, PriceReport, Timeline}

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

  @doc "Like `get_location!/1`, but `nil` instead of raising — for ids that come from a URL."
  def get_location(id), do: Repo.get(Location, id)

  @doc """
  Whether `user` (`nil` for a logged-out visitor) may see — and report at —
  `location`. Approved locations are public; pending and rejected ones are
  admin-only, so an admin can still open them from the moderation queue.
  """
  def visible_to?(%Location{status: "approved"}, _user), do: true
  def visible_to?(%Location{}, %{is_admin: true}), do: true
  def visible_to?(%Location{}, _user), do: false

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

  @run_lookback_days 14

  @doc """
  The current "run" for each utility at each location: how long the
  latest status has held, and how many people have reported it. This is
  what turns single reports into "Power out since Monday 06:46 · 14
  people" — the "me too" count.

  A run is the latest report plus every report before it with the same
  status, going back until a report with a different status (or
  #{@run_lookback_days} days, whichever comes first). So "out, out, on,
  out, out" (newest last) is a two-report "out" run.

  Returns `%{location_id => %{utility => run}}`, where `run` is a map of:

    * `:status` — the latest report's status
    * `:since` — when the earliest report in the run was made
    * `:latest_at` — when the latest report was made
    * `:people` — how many different people reported it (flagged
      reports don't count; reports with no user count one each)
    * `:reporter_ids` — `MapSet` of user ids who reported it, so a page
      can say "You reported this" instead of offering "Me too" again
  """
  def outage_runs(location_ids) when is_list(location_ids) do
    cutoff = DateTime.add(DateTime.utc_now(), -@run_lookback_days * 24 * 60 * 60, :second)
    fields = [:id, :location_id, :utility, :status, :reported_at, :reported_by_id, :is_flagged]

    latest =
      Repo.all(
        from r in OutageReport,
          where: r.location_id in ^location_ids,
          distinct: [r.location_id, r.utility],
          order_by: [desc: r.reported_at, desc: r.id],
          select: map(r, ^fields)
      )

    recent =
      Repo.all(
        from r in OutageReport,
          where: r.location_id in ^location_ids and r.reported_at >= ^cutoff,
          order_by: [desc: r.reported_at, desc: r.id],
          select: map(r, ^fields)
      )
      |> Enum.group_by(&{&1.location_id, &1.utility})

    Enum.reduce(latest, %{}, fn newest, acc ->
      key = {newest.location_id, newest.utility}

      run =
        case Map.get(recent, key, []) do
          [] -> [newest]
          reports -> Enum.take_while(reports, &(&1.status == newest.status))
        end

      counted = Enum.reject(run, & &1.is_flagged)
      reporter_ids = counted |> Enum.map(& &1.reported_by_id) |> Enum.reject(&is_nil/1) |> MapSet.new()
      anonymous = Enum.count(counted, &is_nil(&1.reported_by_id))

      summary = %{
        status: newest.status,
        since: List.last(run).reported_at,
        latest_at: newest.reported_at,
        people: MapSet.size(reporter_ids) + anonymous,
        reporter_ids: reporter_ids
      }

      Map.update(acc, newest.location_id, %{newest.utility => summary}, &Map.put(&1, newest.utility, summary))
    end)
  end

  @price_board_days 14

  @doc """
  Price comparison: for each standard item (`PriceReport.comparable_commodities/0`),
  the latest price at every approved location from the last
  #{@price_board_days} days, cheapest first.

  Only like-for-like prices count: a report must be in the item's
  standard unit (older reports from before units were fixed, e.g.
  tomatoes "per kg", are left out), and flagged reports are left out
  until a moderator clears them. One price per location per item — its
  most recent.

  Returns `%{commodity => [%PriceReport{location: %Location{}, reported_by: ...}, ...]}`;
  an item with no recent prices is missing from the map. Pass
  `days: n` to change the window.
  """
  def price_board(opts \\ []) do
    days = Keyword.get(opts, :days, @price_board_days)
    cutoff = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

    in_standard_unit =
      Enum.reduce(PriceReport.comparable_commodities(), dynamic(false), fn commodity, acc ->
        unit = PriceReport.standard_unit(commodity)
        dynamic([r], ^acc or (r.commodity == ^commodity and r.unit == ^unit))
      end)

    approved = Location.approved()

    Repo.all(
      from r in PriceReport,
        join: l in assoc(r, :location),
        where: l.status == ^approved and not r.is_flagged and r.reported_at >= ^cutoff,
        where: ^in_standard_unit,
        distinct: [r.commodity, r.location_id],
        order_by: [desc: r.reported_at, desc: r.id],
        preload: [:reported_by, location: l]
    )
    |> Enum.group_by(& &1.commodity)
    |> Map.new(fn {commodity, reports} ->
      {commodity, Enum.sort_by(reports, & &1.price_kwacha, Decimal)}
    end)
  end

  @doc """
  What power and water have done at one location since `window_start`:
  a timeline per utility, for the week-of-outages strip on the location
  page. See `Pulse.Reports.Timeline` for how reports become stretches.

  Returns `%{"electricity" => timeline, "water" => timeline}` with only the
  utilities that have something known in the window. Flagged reports are
  left out, the same as the "me too" counts.
  """
  def outage_timeline(location_id, %DateTime{} = window_start, %DateTime{} = now) do
    since = DateTime.add(window_start, -Timeline.hold_seconds(), :second)

    Repo.all(
      from r in OutageReport,
        where:
          r.location_id == ^location_id and not r.is_flagged and r.reported_at >= ^since and
            r.reported_at <= ^now,
        order_by: [asc: r.reported_at, asc: r.id],
        select: map(r, [:utility, :status, :reported_at])
    )
    |> Enum.group_by(& &1.utility)
    |> Enum.map(fn {utility, reports} -> {utility, Timeline.build(reports, window_start, now)} end)
    |> Enum.filter(fn {_utility, timeline} -> timeline.known? end)
    |> Map.new()
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

  @doc "An outage report by id (with its reporter), or `nil`."
  def get_outage_report(id), do: OutageReport |> Repo.get(id) |> Repo.preload(:reported_by)

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

  @doc "A price report by id (with its reporter), or `nil`."
  def get_price_report(id), do: PriceReport |> Repo.get(id) |> Repo.preload(:reported_by)

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
