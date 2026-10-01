defmodule PulseWeb.UserSessionHTML do
  @moduledoc """
  View module for UserSessionController. Only `new.html.heex` (the login
  page) actually renders — `create`/`delete` always redirect.
  """
  use PulseWeb, :html

  embed_templates "user_session_html/*"
end
