defmodule PulseWeb.UserResetPasswordHTML do
  @moduledoc """
  View module for UserResetPasswordController. Only `new.html.heex`
  (the new-password form) renders — `create` either redirects on
  success or re-renders `:new` with the changeset's errors.
  """
  use PulseWeb, :html

  embed_templates "user_reset_password_html/*"
end
