defmodule PulseWeb.UserLoginLive do
  use PulseWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Log in
        <:subtitle>
          Don't have an account?
          <.link navigate={~p"/users/register"} class="font-semibold text-copper-strong hover:underline">
            Sign up
          </.link>
          for one now.
        </:subtitle>
      </.header>

      <.simple_form for={@form} id="login_form" action={~p"/users/log_in"} method="post">
        <.input field={@form[:username]} type="text" label="Username" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
        </:actions>
        <:actions>
          <.button phx-disable-with="Logging in..." class="w-full">
            Log in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-center text-sm text-ink-soft">
        Demo account: <code>demo_resident</code> / <code>pulsedemo123</code>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    form = to_form(%{"username" => nil}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
