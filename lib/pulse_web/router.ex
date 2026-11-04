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

  # Gates plain controller routes (not LiveViews — those use the
  # `:ensure_authenticated` on_mount hook instead) behind a signed-in
  # user. Delegates to `PulseWeb.UserAuth.require_authenticated_user/2`,
  # in scope here via the `import` above. Named `:require_login`, not
  # `:require_authenticated_user` — Phoenix won't let a pipeline share
  # its name with an imported function, and `require_authenticated_user/2`
  # is imported right above from `UserAuth`.
  pipeline :require_login do
    plug :require_authenticated_user
  end

  # Admin-only controller routes. Same naming rule as :require_login: not
  # `:require_admin`, which would clash with the imported
  # `UserAuth.require_admin/2` plug it runs.
  pipeline :admins_only do
    plug :require_admin
  end

  # Proposing a location — a plain controller page rather than a
  # LiveView, so it works even when the live connection can't stay up
  # (see PulseWeb.LocationLive.Show's moduledoc). Declared (and therefore
  # matched) before the "/" scope below: Phoenix's router matches routes
  # in declaration order, so if the live "/locations/:id" route came
  # first, "/locations/new" would be swallowed by it with :id bound to
  # the literal string "new".
  scope "/locations", PulseWeb do
    pipe_through [:browser, :require_login]

    get "/new", LocationController, :new
    post "/", LocationController, :create
  end

  scope "/", PulseWeb do
    pipe_through :browser

    # Public pages: current_user is assigned (for the nav bar) but not
    # required — anyone can browse locations and read reports.
    live_session :current_user,
      on_mount: [{PulseWeb.UserAuth, :mount_current_user}] do
      live "/", LocationLive.Index, :index
      live "/locations/:id", LocationLive.Show, :show
      live "/prices", PriceLive.Index, :index
      live "/prices/:commodity", PriceLive.Show, :show
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

    # Confirming doesn't require being signed in — the link itself is
    # the proof. No shadowing risk against the authenticated routes
    # below: different path shapes ("/settings" vs "/confirm/:token"),
    # not the same shape with one dynamic segment, so declaration order
    # doesn't matter here the way it does for "/locations/new" above.
    get "/confirm/:token", UserConfirmationController, :confirm

    get "/reset_password", UserForgotPasswordController, :new
    post "/reset_password", UserForgotPasswordController, :create
    get "/reset_password/:token", UserResetPasswordController, :new
    post "/reset_password/:token", UserResetPasswordController, :create
  end

  scope "/users", PulseWeb do
    pipe_through [:browser, :require_login]

    get "/settings", UserSettingsController, :edit
    put "/settings/email", UserSettingsController, :update_email
    post "/settings/resend_confirmation", UserSettingsController, :resend_confirmation
  end

  # Admin-only moderation queue — a plain controller page with form POSTs,
  # like the reporting pages below (see PulseWeb.ModerationController).
  scope "/moderation", PulseWeb do
    pipe_through [:browser, :require_login, :admins_only]

    get "/", ModerationController, :index
    post "/locations/:id/approve", ModerationController, :approve
    get "/locations/:id/reject", ModerationController, :new_reject
    post "/locations/:id/reject", ModerationController, :reject
    post "/flags/:type/:id/clear", ModerationController, :clear_flag
  end

  # Reporting and flagging — plain controller pages and form POSTs rather
  # than LiveView events, so they work even when a page's live connection
  # can't stay up (see PulseWeb.LocationLive.Show's moduledoc). Three or
  # more path segments, so none of these can be shadowed by (or shadow)
  # the two-segment live "/locations/:id" route above.
  scope "/locations/:location_id", PulseWeb do
    pipe_through [:browser, :require_login]

    get "/report/outage", ReportController, :new_outage
    post "/outages", ReportController, :create_outage
    get "/report/price", ReportController, :new_price
    post "/prices", ReportController, :create_price
    get "/flag/:type/:report_id", ReportController, :new_flag
    post "/flag/:type/:report_id", ReportController, :create_flag
  end

  # Alerts — saving this browser's push subscription (a fetch from
  # assets/js/app.js) and following or unfollowing a location (tap-only
  # forms on the location page). See Pulse.Alerts.
  scope "/alerts", PulseWeb do
    pipe_through [:browser, :require_login]

    post "/subscriptions", PushSubscriptionController, :create
    post "/locations/:location_id", AlertController, :follow_location
    delete "/locations/:location_id", AlertController, :unfollow_location
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
