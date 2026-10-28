defmodule Pulse.Accounts.UserNotifier do
  @moduledoc """
  Builds and sends the two transactional emails Pulse sends: confirm
  your email, and reset your password. Delivered through `Pulse.Mailer`
  (Swoosh) — the Local adapter in dev, the Test adapter in test, and in
  prod the Logger adapter until `RESEND_API_KEY` is set, Resend once it
  is (see `config/runtime.exs`).

  The From address defaults to Resend's own `onboarding@resend.dev`
  sandbox sender, which works before any domain is verified on the
  Resend account — set `MAILER_FROM_EMAIL` once a real domain is
  verified there, so mail comes from `pulse-zm.<yourdomain>` instead.
  """

  import Swoosh.Email

  alias Pulse.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Pulse", Application.get_env(:pulse, :mailer_from, "onboarding@resend.dev")})
      |> subject(subject)
      |> text_body(body)

    # Email is best-effort everywhere it's used (see the callers), so a
    # mail adapter that's down or misconfigured comes back as an error
    # tuple the caller can log, instead of an exit that crashes the
    # request after the account change it belongs to has already saved.
    try do
      with {:ok, _metadata} <- Mailer.deliver(email) do
        {:ok, email}
      end
    catch
      :exit, reason -> {:error, {:mailer_unavailable, reason}}
    end
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your Pulse account", """
    Hi #{user.username},

    Confirm your email by visiting the link below. This unlocks password
    reset by email — Pulse works fine either way in the meantime.

    #{url}

    If you didn't create a Pulse account, you can ignore this.
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your Pulse password", """
    Hi #{user.username},

    Someone (hopefully you) asked to reset the password on your Pulse
    account. Visit the link below to set a new one — it expires in 24
    hours.

    #{url}

    If you didn't request this, you can safely ignore this email; your
    password won't change.
    """)
  end
end
