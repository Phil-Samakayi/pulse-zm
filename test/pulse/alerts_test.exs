defmodule Pulse.AlertsTest do
  use Pulse.DataCase, async: true

  import Pulse.AccountsFixtures
  import Pulse.ReportsFixtures

  alias Pulse.Alerts
  alias Pulse.Alerts.PushSubscription
  alias Pulse.Reports

  describe "subscriptions" do
    test "saves a browser's subscription" do
      user = user_fixture()

      assert {:ok, %PushSubscription{endpoint: "https://push.example/a", user_id: user_id}} =
               Alerts.save_subscription(user, subscription_params("https://push.example/a"))

      assert user_id == user.id
    end

    test "saving the same browser again moves it to whoever is logged in now" do
      first = user_fixture()
      second = user_fixture()

      {:ok, _} = Alerts.save_subscription(first, subscription_params("https://push.example/shared"))
      {:ok, _} = Alerts.save_subscription(second, subscription_params("https://push.example/shared"))

      assert [%{user_id: user_id}] = Repo.all(PushSubscription)
      assert user_id == second.id
    end

    test "rejects something that isn't a subscription" do
      user = user_fixture()

      assert {:error, :invalid_subscription} = Alerts.save_subscription(user, %{"endpoint" => "x"})

      assert {:error, %Ecto.Changeset{}} =
               Alerts.save_subscription(user, subscription_params("http://not-https.example"))
    end
  end

  describe "following a location" do
    test "follow, check, follow again, unfollow" do
      user = user_fixture()
      location = location_fixture()

      refute Alerts.following_location?(user, location.id)
      assert {:ok, _} = Alerts.follow_location(user, location)
      assert Alerts.following_location?(user, location.id)
      assert {:ok, :already_following} = Alerts.follow_location(user, location)

      assert :ok = Alerts.unfollow_location(user, location)
      refute Alerts.following_location?(user, location.id)
    end

    test "nobody is following anything when logged out" do
      refute Alerts.following_location?(nil, location_fixture().id)
    end
  end

  describe "notify_outage/1" do
    setup do
      location = location_fixture(name: "Kabwata")
      follower = user_fixture()
      Alerts.save_subscription(follower, subscription_params("https://push.example/follower"))
      {:ok, _} = Alerts.follow_location(follower, location)

      %{location: location, follower: follower}
    end

    test "tells followers when power goes out, linking to the place", %{location: location} do
      report = report!(location, "down")

      assert {:sent, 1} = Alerts.notify_outage(report)

      assert_received {:push, "https://push.example/follower",
                       %{"title" => "Power is out in Kabwata", "url" => url, "tag" => tag}}

      assert url == "/locations/#{location.id}"
      assert tag == "outage-#{location.id}-electricity"
    end

    test "tells them again when it comes back, but not for a me-too in between", %{
      location: location
    } do
      Alerts.notify_outage(report!(location, "down"))
      assert_received {:push, _, %{"title" => "Power is out in Kabwata"}}

      assert :unchanged = Alerts.notify_outage(report!(location, "down"))
      refute_received {:push, _, _}

      assert {:sent, 1} = Alerts.notify_outage(report!(location, "up"))
      assert_received {:push, _, %{"title" => "Power is back in Kabwata"}}
    end

    test "a first report that everything is fine isn't news", %{location: location} do
      assert :unchanged = Alerts.notify_outage(report!(location, "up"))
      refute_received {:push, _, _}
    end

    test "keeps power and water separate", %{location: location} do
      Alerts.notify_outage(report!(location, "down", "electricity"))
      assert_received {:push, _, %{"title" => "Power is out in Kabwata"}}

      assert {:sent, 1} = Alerts.notify_outage(report!(location, "down", "water"))
      assert_received {:push, _, %{"title" => "Water is out in Kabwata"}}
    end

    test "doesn't notify the person who reported it", %{location: location, follower: follower} do
      {:ok, report} =
        Reports.create_outage_report(
          valid_outage_attrs(location_id: location.id, reported_by_id: follower.id, status: "down")
        )

      assert {:sent, 0} = Alerts.notify_outage(report)
      refute_received {:push, _, _}
    end

    test "doesn't notify people who don't follow the place" do
      elsewhere = location_fixture()

      assert {:sent, 0} = Alerts.notify_outage(report!(elsewhere, "down"))
      refute_received {:push, _, _}
    end

    test "removes a subscription the browser has given up on", %{location: location} do
      user = user_fixture()
      {:ok, gone} = Alerts.save_subscription(user, subscription_params("https://push.example/expired-1"))
      {:ok, _} = Alerts.follow_location(user, location)

      assert {:sent, 1} = Alerts.notify_outage(report!(location, "down"))
      refute Repo.get(PushSubscription, gone.id)
    end
  end

  defp subscription_params(endpoint) do
    %{"endpoint" => endpoint, "keys" => %{"p256dh" => "public-key", "auth" => "secret"}}
  end

  # A fresh reporter each time, so the duplicate-report cooldown never
  # gets in the way.
  defp report!(location, status, utility \\ "electricity") do
    {:ok, report} =
      Reports.create_outage_report(
        valid_outage_attrs(
          location_id: location.id,
          reported_by_id: user_fixture().id,
          utility: utility,
          status: status
        )
      )

    report
  end
end
