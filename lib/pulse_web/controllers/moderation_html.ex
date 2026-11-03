defmodule PulseWeb.ModerationHTML do
  @moduledoc "Templates for `PulseWeb.ModerationController` (`moderation_html/*.html.heex`)."

  use PulseWeb, :html

  import PulseWeb.ReportFormat,
    only: [outage_short: 1, price_summary: 1, reporter_name: 1, full_time: 1]

  embed_templates "moderation_html/*"

  @doc "A small one-button form that POSTs to `action` — works without a live connection."
  attr :action, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def post_button(assigns) do
    ~H"""
    <.form for={%{}} action={@action} method="post" class="inline">
      <button
        type="submit"
        class={["rounded px-2 py-1 text-sm font-semibold hover:underline", @class]}
      >
        {render_slot(@inner_block)}
      </button>
    </.form>
    """
  end

  defp submitter_name(%{submitted_by: %{username: username}}), do: username
  defp submitter_name(_), do: "unknown"

  defp group_label("residential"), do: "Residential area"
  defp group_label("market"), do: "Market"
  defp group_label(other), do: other

  defp blank_dash(""), do: "—"
  defp blank_dash(nil), do: "—"
  defp blank_dash(reason), do: reason
end
