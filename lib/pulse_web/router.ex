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

    # Requires login — on_mount bounces an anonymous visitor to the
    # login page itself. Declared (and therefore matched) before
    # "/locations/:id" below: Phoenix's router compiles routes in
    # declaration order, so if the dynamic route came first,
    # "/locations/new" would be swallowed by it with :id bound to the
    # literal string "new".
    live_session :require_user,
      on_mount: [{PulseWeb.UserAuth, :ensure_authenticated}] do
      live "/locations/new", LocationLive.New, :new
    end

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

    # Login and registration are plain controller-rendered pages, not
    # LiveViews — see the moduledocs on UserSessionController.new/2 and
    # UserRegistrationController.new/2 for why (both used to be LiveViews
    # and both hit the same bug: a dropped/reconnected socket remounts
    # the page from scratch and wipes out whatever had been typed,
    # stealing focus along with it). Each `new` action redirects an
    # already-logged-in visitor away itself, replacing the
    # `:redirect_if_user_is_authenticated` on_mount hook this used to
    # lean on.
    get "/log_in", UserSessionController, :new
    post "/log_in", UserSessionController, :create
    delete "/log_out", UserSessionController, :delete

    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create
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
