defmodule PulseWeb.UserSettingsHTML do
  @moduledoc """
  View module for UserSettingsController. Only `edit.html.heex`
  renders — `update_email` and `resend_confirmation` either redirect
  or (on a validation error) re-render `:edit`.
  """
  use PulseWeb, :html

  embed_templates "user_settings_html/*"
end
