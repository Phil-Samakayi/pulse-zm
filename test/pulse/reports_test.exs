defmodule Pulse.ReportsTest do
  use Pulse.DataCase, async: true

  alias Pulse.Reports
  alias Pulse.Reports.Location

  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  describe "locations" do
    test "list_locations/0 only returns approved locations" do
      approved = location_fixture()
      user = user_fixture()
      {:ok, pending} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))

      names = Reports.list_locations() |> Enum.map(& &1.name)

      assert approved.name in names
      refute pending.name in names
    end

    test "submit_location/1 always lands as pending, regardless of attrs" do
      user = user_fixture()

      {:ok, location} =
        Reports.submit_location(valid_location_attrs(submitted_by_id: user.id, status: "approved"))

      assert location.status == Location.pending()
      assert location.submitted_by_id == user.id
    end

    test "submit_location/1 is rate-limited per user" do
      user = user_fixture()

      for _ <- 1..3 do
        assert {:ok, _} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))
      end

      assert {:error, changeset} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))
      assert errors_on(changeset).base |> List.first() =~ "too quickly"
    end

    test "approve_location/1 makes a pending location visible on the public list" do
      user = user_fixture()
      {:ok, location} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))

      {:ok, approved} = Reports.approve_location(location)

      assert approved.status == Location.approved()
      assert approved.name in Enum.map(Reports.list_locations(), & &1.name)
    end

    test "reject_location/2 requires and stores a reason" do
      user = user_fixture()
      {:ok, location} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))

      {:ok, rejected} = Reports.reject_location(location, "Duplicate of an existing area")

      assert rejected.status == Location.rejected()
      assert rejected.rejection_note == "Duplicate of an existing area"
    end

    test "reject_location/2 fails validation with a blank reason" do
      user = user_fixture()
      {:ok, location} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))

      {:error, changeset} = Reports.reject_location(location, "")

      assert "is required when rejecting a location" in errors_on(changeset).rejection_note
    end

    test "list_pending_locations/0 only returns pending ones" do
      user = user_fixture()
      {:ok, first} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))
      {:ok, second} = Reports.submit_location(valid_location_attrs(submitted_by_id: user.id))
      _approved = location_fixture()

      pending_ids = Reports.list_pending_locations() |> Enum.map(& &1.id) |> Enum.sort()

      assert pending_ids == Enum.sort([first.id, second.id])
    end
  end

  describe "outage reports" do
    setup do
      %{user: user_fixture(), location: location_fixture()}
    end

    test "create_outage_report/1 inserts a report and broadcasts it", %{user: user, location: location} do
      Reports.subscribe(location.id)

      attrs = valid_outage_attrs(location_id: location.id, reported_by_id: user.id)
      assert {:ok, report} = Reports.create_outage_report(attrs)

      assert report.location_id == location.id
      assert report.reported_by_id == user.id
      assert report.reported_at
      assert_received {:report_created, ^report}
    end

    test "rejects a duplicate report for the same utility within the cooldown window", %{
      user: user,
      location: location
    } do
      attrs = valid_outage_attrs(location_id: location.id, reported_by_id: user.id)
      assert {:ok, _} = Reports.create_outage_report(attrs)

      assert {:error, changeset} = Reports.create_outage_report(attrs)
      assert errors_on(changeset).base |> List.first() =~ "already reported this"
    end

    test "allows a report for a different utility right after", %{user: user, location: location} do
      assert {:ok, _} =
               Reports.create_outage_report(
                 valid_outage_attrs(location_id: location.id, reported_by_id: user.id, utility: "electricity")
               )

      assert {:ok, _} =
               Reports.create_outage_report(
                 valid_outage_attrs(location_id: location.id, reported_by_id: user.id, utility: "water")
               )
    end

    test "is rate-limited after 5 reports in a minute", %{user: user} do
      # A different location per report dodges the per-location/utility
      # duplicate cooldown so this isolates the rate limit specifically —
      # the rate limit is keyed on the user alone, not the location.
      for _ <- 1..5 do
        location = location_fixture()

        assert {:ok, _} =
                 Reports.create_outage_report(
                   valid_outage_attrs(location_id: location.id, reported_by_id: user.id)
                 )
      end

      extra = location_fixture()

      assert {:error, changeset} =
               Reports.create_outage_report(
                 valid_outage_attrs(location_id: extra.id, reported_by_id: user.id)
               )

      assert errors_on(changeset).base |> List.first() =~ "too quickly"
    end
  end

  describe "price reports" do
    setup do
      %{user: user_fixture(), location: location_fixture()}
    end

    test "create_price_report/1 inserts a report and broadcasts it", %{user: user, location: location} do
      Reports.subscribe(location.id)

      attrs = valid_price_attrs(location_id: location.id, reported_by_id: user.id)
      assert {:ok, report} = Reports.create_price_report(attrs)

      assert report.location_id == location.id
      assert_received {:report_created, ^report}
    end

    test "requires commodity_other when commodity is \"other\"", %{user: user, location: location} do
      attrs = valid_price_attrs(location_id: location.id, reported_by_id: user.id, commodity: "other")

      assert {:error, changeset} = Reports.create_price_report(attrs)
      assert "is required when commodity is \"Other\"" in errors_on(changeset).commodity_other
    end

    test "rejects a duplicate report for the same commodity within the cooldown window", %{
      user: user,
      location: location
    } do
      attrs = valid_price_attrs(location_id: location.id, reported_by_id: user.id)
      assert {:ok, _} = Reports.create_price_report(attrs)

      assert {:error, changeset} = Reports.create_price_report(attrs)
      assert errors_on(changeset).base |> List.first() =~ "already reported this"
    end

    test "is rate-limited after 5 reports in a minute", %{user: user, location: location} do
      # A different commodity per report dodges the duplicate cooldown
      # (keyed on user+location+commodity) so this isolates the rate limit.
      for commodity <- ["mealie_meal", "charcoal", "kapenta", "cooking_oil", "tomatoes"] do
        assert {:ok, _} =
                 Reports.create_price_report(
                   valid_price_attrs(location_id: location.id, reported_by_id: user.id, commodity: commodity)
                 )
      end

      assert {:error, changeset} =
               Reports.create_price_report(
                 valid_price_attrs(
                   location_id: location.id,
                   reported_by_id: user.id,
                   commodity: "other",
                   commodity_other: "Eggs"
                 )
               )

      assert errors_on(changeset).base |> List.first() =~ "too quickly"
    end
  end

  describe "flagging" do
    setup do
      user = user_fixture()
      location = location_fixture()

      {:ok, outage} =
        Reports.create_outage_report(valid_outage_attrs(location_id: location.id, reported_by_id: user.id))

      {:ok, price} =
        Reports.create_price_report(valid_price_attrs(location_id: location.id, reported_by_id: user.id))

      %{outage: outage, price: price}
    end

    test "flag_outage_report/2 marks a report flagged with a reason", %{outage: outage} do
      {:ok, flagged} = Reports.flag_outage_report(outage, %{"flag_reason" => "Looks wrong"})

      assert flagged.is_flagged
      assert flagged.flag_reason == "Looks wrong"
    end

    test "clear_outage_flag/1 clears a flagged report", %{outage: outage} do
      {:ok, flagged} = Reports.flag_outage_report(outage, %{"flag_reason" => "Looks wrong"})
      {:ok, cleared} = Reports.clear_outage_flag(flagged)

      refute cleared.is_flagged
      assert cleared.flag_reason == ""
    end

    test "flag_price_report/2 and clear_price_flag/1 round-trip the same way", %{price: price} do
      {:ok, flagged} = Reports.flag_price_report(price, %{"flag_reason" => "Seems too high"})
      assert flagged.is_flagged

      {:ok, cleared} = Reports.clear_price_flag(flagged)
      refute cleared.is_flagged
    end

    test "list_flagged_reports/0 only returns flagged reports", %{outage: outage, price: price} do
      assert Reports.list_flagged_reports() == %{outages: [], prices: []}

      {:ok, _} = Reports.flag_outage_report(outage, %{"flag_reason" => "x"})
      {:ok, _} = Reports.flag_price_report(price, %{"flag_reason" => "y"})

      flagged = Reports.list_flagged_reports()

      assert [%{id: outage_id}] = flagged.outages
      assert outage_id == outage.id

      assert [%{id: price_id}] = flagged.prices
      assert price_id == price.id
    end
  end

  describe "location_summaries/1" do
    test "picks the newest outage report per utility, electricity first" do
      location = location_fixture()

      insert_outage!(location, "water", "down", minutes_ago: 30)
      insert_outage!(location, "electricity", "down", minutes_ago: 90)
      newest_power = insert_outage!(location, "electricity", "up", minutes_ago: 10)

      summary = Reports.location_summaries([location.id])[location.id]

      assert [%{utility: "electricity", status: "up", id: power_id}, %{utility: "water", status: "down"}] =
               summary.outages

      assert power_id == newest_power.id
    end

    test "reports when prices were last updated" do
      location = location_fixture()

      insert_price!(location, minutes_ago: 120)
      newest = insert_price!(location, minutes_ago: 5)

      summary = Reports.location_summaries([location.id])[location.id]

      assert summary.outages == []
      assert summary.prices_updated_at == newest.reported_at
    end

    test "leaves out locations with no reports, and only looks at the ids asked for" do
      quiet = location_fixture()
      busy = location_fixture()
      not_asked = location_fixture()

      insert_outage!(busy, "electricity", "down", minutes_ago: 1)
      insert_outage!(not_asked, "electricity", "down", minutes_ago: 1)

      summaries = Reports.location_summaries([quiet.id, busy.id])

      assert Map.keys(summaries) == [busy.id]
      assert Reports.location_summaries([]) == %{}
    end
  end

  defp minutes_ago(minutes) do
    DateTime.utc_now() |> DateTime.add(-minutes * 60) |> DateTime.truncate(:second)
  end

  # Inserted directly rather than through create_*_report/1, because those
  # always stamp reported_at with "now" — these tests need control over it.
  defp insert_outage!(location, utility, status, minutes_ago: minutes) do
    %Pulse.Reports.OutageReport{
      location_id: location.id,
      utility: utility,
      status: status,
      reported_at: minutes_ago(minutes)
    }
    |> Pulse.Repo.insert!()
  end

  defp insert_price!(location, minutes_ago: minutes) do
    %Pulse.Reports.PriceReport{
      location_id: location.id,
      commodity: "mealie_meal",
      unit: "25kg bag",
      price_kwacha: Decimal.new("450.00"),
      reported_at: minutes_ago(minutes)
    }
    |> Pulse.Repo.insert!()
  end
end
