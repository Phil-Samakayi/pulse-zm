defmodule Pulse.Alerts do
  @moduledoc """
  Alerts: phone notifications about the places a user follows.

  Two parts:

    * **Subscriptions** — the browsers a user has allowed notifications
      on (`Pulse.Alerts.PushSubscription`), saved by
      `PulseWeb.AlertController` when the browser signs up.
    * **Alerts** — what each user wants to hear about
      (`Pulse.Alerts.Alert`). For now: location alerts, "tell me when
      power or water changes here".

  `notify_outage/1` runs after every new outage report
  (`PulseWeb.ReportController` calls `notify_outage_async/1`). It only
  notifies when the report *changes* the status — "Power is out in
  Kabwata", "Water is back in Matero" — never for a "me too" that
  confirms what's already known, and never to the person who reported it.
  """

  import Ecto.Query, warn: false

  alias Pulse.Repo
  alias Pulse.Alerts.{Alert, PushSubscription}
  alias Pulse.Reports
  alias Pulse.Reports.OutageReport

  ## Subscriptions

  @doc """
  Saves a browser's push subscription for `user`, from the JSON the
  browser's `pushManager.subscribe()` produced:
  `%{"endpoint" => ..., "keys" => %{"p256dh" => ..., "auth" => ...}}`.
  Saving the same browser again updates it (and moves it to `user` if
  someone else was logged in on it before).
  """
  def save_subscription(user, %{"endpoint" => endpoint, "keys" => %{"p256dh" => p256dh, "auth" => auth}}) do
    %PushSubscription{}
    |> PushSubscription.changeset(%{
      user_id: user.id,
      endpoint: endpoint,
      p256dh: p256dh,
      auth: auth
    })
    |> Repo.insert(
      on_conflict: {:replace, [:user_id, :p256dh, :auth, :updated_at]},
      conflict_target: :endpoint
    )
  end

  def save_subscription(_user, _params), do: {:error, :invalid_subscription}

  def delete_subscription(%PushSubscription{} = subscription), do: Repo.delete(subscription)

  ## Location alerts

  def following_location?(nil, _location_id), do: false

  def following_location?(user, location_id) do
    Repo.exists?(from a in Alert, where: a.user_id == ^user.id and a.location_id == ^location_id)
  end

  @doc "Start following a location. Following it again is a no-op — still one alert."
  def follow_location(user, location) do
    if following_location?(user, location.id) do
      {:ok, :already_following}
    else
      %Alert{}
      |> Alert.location_changeset(%{user_id: user.id, location_id: location.id})
      |> Repo.insert()
    end
  end

  def unfollow_location(user, location) do
    Repo.delete_all(from a in Alert, where: a.user_id == ^user.id and a.location_id == ^location.id)
    :ok
  end

  ## Notifying

  @doc """
  `notify_outage/1` in the background (a supervised task), so reporting
  doesn't wait on push services. Runs inline instead when
  `config :pulse, :alerts_inline` is set, as in tests.
  """
  def notify_outage_async(%OutageReport{} = report) do
    if Application.get_env(:pulse, :alerts_inline, false) do
      notify_outage(report)
    else
      Task.Supervisor.start_child(Pulse.TaskSupervisor, fn -> notify_outage(report) end)
    end

    :ok
  end

  @doc """
  Notify everyone following `report`'s location, if the report changes
  the status there. Returns `{:sent, count}` or `:unchanged`.
  """
  def notify_outage(%OutageReport{} = report) do
    if status_changed?(report) do
      location = Reports.get_location!(report.location_id)
      message = outage_message(report, location)

      sent =
        report
        |> outage_recipients()
        |> Enum.count(&(send_to(&1, message) == :ok))

      {:sent, sent}
    else
      :unchanged
    end
  end

  # The first report at a place only counts as news if something is
  # *out*; "power is on" with nothing before it isn't worth a ping.
  defp status_changed?(report) do
    previous =
      Repo.one(
        from r in OutageReport,
          where:
            r.location_id == ^report.location_id and r.utility == ^report.utility and
              r.id < ^report.id,
          # Insertion order, not reported_at: the report just before this
          # one, even if both landed in the same second.
          order_by: [desc: r.id],
          limit: 1
      )

    case previous do
      nil -> report.status == OutageReport.down()
      previous -> previous.status != report.status
    end
  end

  # Every subscription of every user following the location, except the
  # reporter's own.
  defp outage_recipients(report) do
    reporter_id = report.reported_by_id || -1

    Repo.all(
      from s in PushSubscription,
        join: a in Alert,
        on: a.user_id == s.user_id,
        where: a.location_id == ^report.location_id and s.user_id != ^reporter_id,
        distinct: true
    )
  end

  defp outage_message(report, location) do
    utility = if report.utility == OutageReport.electricity(), do: "Power", else: "Water"

    title =
      if report.status == OutageReport.up(),
        do: "#{utility} is back in #{location.name}",
        else: "#{utility} is out in #{location.name}"

    %{
      title: title,
      body: "Just reported on Pulse. Tap to see details.",
      url: "/locations/#{location.id}",
      # A newer alert about the same place and utility replaces the old
      # one on the phone instead of stacking up.
      tag: "outage-#{location.id}-#{report.utility}"
    }
  end

  defp send_to(subscription, message) do
    case Pulse.Push.deliver(PushSubscription.to_json(subscription), message) do
      :ok ->
        :ok

      {:error, :expired} ->
        delete_subscription(subscription)
        :expired

      {:error, _reason} ->
        :error
    end
  end
end
