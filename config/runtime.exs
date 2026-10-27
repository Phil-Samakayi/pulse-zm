import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/pulse start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :pulse, PulseWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6"), do: [:inet6], else: []

  # Set ECTO_SSL=true for a managed Postgres that requires SSL (e.g. Neon).
  # Uses the OS trust store via :public_key.cacerts_get/0 (OTP 25+), which
  # needs the ca-certificates package installed in the runtime image --
  # already present in this project's Dockerfile.
  #
  # Checked loosely (trimmed, case-insensitive, anything but an explicit
  # "false"/"0"/empty counts as on) so a stray space or "True" in a
  # dashboard env var field doesn't silently disable SSL.
  ecto_ssl? =
    case System.get_env("ECTO_SSL") do
      nil -> false
      val -> String.downcase(String.trim(val)) not in ["", "false", "0"]
    end

  maybe_ssl =
    if ecto_ssl? do
      [ssl: [cacerts: :public_key.cacerts_get()]]
    else
      []
    end

  config :pulse,
         Pulse.Repo,
         [
           url: database_url,
           pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
           socket_options: maybe_ipv6
         ] ++ maybe_ssl

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # The URL scheme/port used to build links (in emails, redirects, etc).
  # Defaults to https/443 for when a real domain + TLS is in front of the
  # app. While running on the bare Oracle VM IP with no domain yet, the
  # docker-compose.yml sets PHX_SCHEME=http and PHX_URL_PORT=80 so
  # generated links point somewhere that actually works.
  url_scheme = System.get_env("PHX_SCHEME") || "https"
  url_port = String.to_integer(System.get_env("PHX_URL_PORT") || "443")

  config :pulse, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :pulse, PulseWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :pulse, PulseWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :pulse, PulseWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Confirmation and password-reset emails go out through Resend
  # (https://resend.com) once RESEND_API_KEY is set — get a key from
  # the Resend dashboard and set it as an env var on Render (or
  # wherever this ends up running). Until then, this falls back to the
  # Local adapter, same as dev: emails are generated and immediately
  # discarded (no mailbox route is mounted in prod to view them), which
  # is harmless since nothing in the app requires email to function —
  # see Pulse.Accounts' moduledoc on "soft" confirmation.
  #
  # MAILER_FROM_EMAIL defaults to Resend's onboarding@resend.dev sandbox
  # sender, which works before any domain is verified on the account.
  # Set it to something like "pulse@yourdomain.com" once a real domain
  # is verified in the Resend dashboard, so confirmation/reset emails
  # come from your own domain instead.
  if resend_api_key = System.get_env("RESEND_API_KEY") do
    config :pulse, Pulse.Mailer,
      adapter: Resend.Swoosh.Adapter,
      api_key: resend_api_key
  end

  if mailer_from_email = System.get_env("MAILER_FROM_EMAIL") do
    config :pulse, :mailer_from, mailer_from_email
  end
end
