defmodule PulseWeb.Router do
  use PulseWeb, :router

  import PulseWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PulseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PulseWeb do
    pipe_through :browser

    # Public pages: current_user is assigned (for the nav bar) but not
    # required — anyone can browse locations and read reports.
    live_session :current_user,
      on_mount: [{PulseWeb.UserAuth, :mount_current_user}] do
      live "/", LocationLive.Index, :index
      live "/locations/:id", LocationLive.Show, :show
    end

    # Admin-only.
    live_session :require_admin,
      on_mount: [{PulseWeb.UserAuth, :ensure_admin}] do
      live "/moderation", ModerationLive.Index, :index
    end
  end

  scope "/users", PulseWeb do
    pipe_through :browser

    # A logged-in user visiting this gets bounced to "/" instead.
    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PulseWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/register", UserRegistrationLive, :new
    end

    # Login is a plain controller-rendered page, not a LiveView — see the
    # moduledoc on UserSessionController.new/2 for why (it fixes the
    # input-focus-loss bug caused by the login socket dropping/reconnecting).
    # Logout is also a real HTTP action, not a socket event — see the
    # moduledoc on UserSessionController for why login/logout can't be
    # socket events.
    get "/log_in", UserSessionController, :new
    post "/log_in", UserSessionController, :create
    delete "/log_out", UserSessionController, :delete
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pulse, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PulseWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
