defmodule PulseWeb.UserRegistrationHTML do
  @moduledoc """
  View module for UserRegistrationController. Only `new.html.heex` (the
  registration page) actually renders — `create` either redirects or
  re-renders `:new` with the changeset's errors on failure.
  """
  use PulseWeb, :html

  embed_templates "user_registration_html/*"
end
