defmodule PulseWeb.UserForgotPasswordHTML do
  @moduledoc """
  View module for UserForgotPasswordController. Only `new.html.heex`
  (the request form) actually renders — `create` always redirects.
  """
  use PulseWeb, :html

  embed_templates "user_forgot_password_html/*"
end
