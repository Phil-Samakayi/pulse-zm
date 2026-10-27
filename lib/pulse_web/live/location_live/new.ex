defmodule PulseWeb.LocationLive.New do
  @moduledoc """
  Propose a new location for review. Requires login — gated by the
  `:ensure_authenticated` on_mount hook (see the router), which bounces
  an anonymous visitor to the login page with a flash before this even
  mounts. Submissions always land with status "pending" and only become
  visible to everyone else once an admin approves them from the
  moderation queue (`PulseWeb.ModerationLive.Index`).

  Includes a honeypot field (`:website`, see `Pulse.Reports.Location`) —
  hidden from real users via CSS, so a human never fills it in, but a
  spam bot's generic form-filler often will. If it comes back non-empty
  on submit, the handler pretends the submission succeeded (same flash,
  same redirect) without actually inserting anything, so the bot gets no
  signal that it was caught.
  """

  use PulseWeb, :live_view

  alias Pulse.Reports
  alias Pulse.Reports.Location

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Propose a location
        <:subtitle>
          Suggest a residential area or market that isn't listed yet. An admin reviews it
          before it goes live for everyone.
        </:subtitle>
      </.header>

      <.simple_form for={@form} id="location_form" phx-change="validate" phx-submit="submit">
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:city]} type="text" label="City" required />
        <.input
          field={@form[:location_type]}
          type="select"
          label="Type"
          prompt="Choose one"
          options={location_type_options()}
        />

        <div class="absolute -left-[9999px]" aria-hidden="true">
          <.input
            field={@form[:website]}
            type="text"
            label="Leave this field blank"
            tabindex="-1"
            autocomplete="off"
          />
        </div>

        <:actions>
          <.button phx-disable-with="Submitting..." class="w-full">Submit for review</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Propose a location")
     |> assign_form(Reports.change_location_submission())}
  end

  def handle_event("validate", %{"location" => params}, socket) do
    changeset =
      Reports.change_location_submission(%Location{}, params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"location" => params}, socket) do
    if honeypot_filled?(params) do
      {:noreply, socket |> flash_submitted() |> push_navigate(to: ~p"/")}
    else
      attrs = Map.put(params, "submitted_by_id", socket.assigns.current_user.id)

      case Reports.submit_location(attrs) do
        {:ok, _location} ->
          {:noreply, socket |> flash_submitted() |> push_navigate(to: ~p"/")}

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    end
  end

  defp honeypot_filled?(params), do: (params["website"] || "") != ""

  defp flash_submitted(socket) do
    put_flash(socket, :info, "Thanks — submitted for review. An admin will take a look soon.")
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: "location"))
  end

  defp location_type_options, do: Enum.map(Location.location_types(), &{group_label(&1), &1})

  defp group_label("residential"), do: "Residential area"
  defp group_label("market"), do: "Market"
  defp group_label(other), do: other
end
