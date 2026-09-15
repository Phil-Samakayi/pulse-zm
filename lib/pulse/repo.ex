defmodule Pulse.Repo do
  use Ecto.Repo,
    otp_app: :pulse,
    adapter: Ecto.Adapters.SQLite3
end
