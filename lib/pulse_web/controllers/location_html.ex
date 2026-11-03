defmodule PulseWeb.LocationHTML do
  @moduledoc "Templates for `PulseWeb.LocationController` (`location_html/*.html.heex`)."

  use PulseWeb, :html

  import PulseWeb.ReportHTML, only: [choice_group: 1, honeypot: 1]

  alias Pulse.Reports.Location

  embed_templates "location_html/*"

  defp location_type_options,
    do: [{"Residential area", Location.residential()}, {"Market", Location.market()}]
end
