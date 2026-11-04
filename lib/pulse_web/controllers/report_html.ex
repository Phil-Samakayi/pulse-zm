defmodule PulseWeb.ReportHTML do
  @moduledoc """
  Templates for `PulseWeb.ReportController`: the outage form, the price
  form and the flag form (`report_html/*.html.heex`).
  """

  use PulseWeb, :html

  import PulseWeb.ReportFormat

  alias Pulse.Reports.{OutageReport, PriceReport}

  embed_templates "report_html/*"

  @doc """
  A row of large, tappable choices for one field: radio buttons drawn as
  pills. Quicker on a phone than a dropdown. Shows the field's errors
  whenever there are any; a changeset only carries errors after a
  submit, so a fresh form shows none.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true, doc: "a list of {label, value} tuples"

  def choice_group(assigns) do
    assigns = assign(assigns, :errors, Enum.map(assigns.field.errors, &translate_error/1))

    ~H"""
    <fieldset>
      <legend class="block text-sm font-semibold leading-6 text-ink-soft">{@label}</legend>
      <div class="mt-2 flex flex-wrap gap-2">
        <label :for={{text, value} <- @options} class="cursor-pointer">
          <input
            type="radio"
            name={@field.name}
            value={value}
            checked={to_string(@field.value) == value}
            required
            class="peer sr-only"
          />
          <span class="inline-block rounded-full border border-line bg-paper-raised px-4 py-2 text-sm font-semibold text-ink peer-checked:border-copper peer-checked:bg-amber-bg peer-checked:text-copper-strong peer-focus-visible:ring-2 peer-focus-visible:ring-copper">
            {text}
          </span>
        </label>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  @doc "The hidden anti-spam field — see `Pulse.Reports.OutageReport`'s `:website`."
  attr :field, Phoenix.HTML.FormField, required: true

  def honeypot(assigns) do
    ~H"""
    <div class="absolute -left-[9999px]" aria-hidden="true">
      <.input field={@field} type="text" label="Leave this field blank" tabindex="-1" autocomplete="off" />
    </div>
    """
  end

  @doc "Back link to the location page, shared by all three forms."
  attr :location, :any, required: true

  def back_to_location(assigns) do
    ~H"""
    <.link
      navigate={~p"/locations/#{@location.id}"}
      class="text-sm font-semibold leading-6 text-copper-strong hover:text-copper"
    >
      <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> {@location.name}
    </.link>
    """
  end

  defp utility_options, do: Enum.map(OutageReport.utilities(), &{utility_label(&1), &1})

  defp status_options,
    do: Enum.map([OutageReport.up(), OutageReport.down()], &{String.capitalize(status_word(&1)), &1})

  # "Mealie meal · 25kg bag", "Tomatoes · pile", "Other".
  defp commodity_options do
    Enum.map(PriceReport.commodities(), fn commodity ->
      label =
        case PriceReport.standard_unit(commodity) do
          nil -> PriceReport.commodity_label(commodity)
          unit -> "#{PriceReport.commodity_label(commodity)} · #{unit}"
        end

      {label, commodity}
    end)
  end
end
