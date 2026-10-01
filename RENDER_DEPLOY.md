# Deploying Pulse to Render (web) + Neon (Postgres)

No card needed anywhere in this path. Render hosts the app container free
(750 hrs/month covers one always-on service, with a 15-min-idle sleep and
~1 min cold start). Neon hosts Postgres free permanently (0.5 GB storage,
100 CU-hours/month, its own much-shorter scale-to-zero after 5 min idle —
independent of Render's sleep).

This replaces the Oracle path for now — `DEPLOY.md` is still there if you
get the card verification sorted later and want to switch/compare.

## 1. Create the Neon database

1. Go to neon.com → sign up (GitHub OAuth is easiest) → no card required.
2. Create a project (any name, e.g. `pulse`). Note the region — pick one
   close to you if offered.
3. In the project dashboard, open **Connection Details**. Copy the
   connection string.
4. **Strip the query string off it.** Neon's copy button gives you
   something like:
   ```
   postgresql://user:AbC123@ep-cool-darkness-123456.region.aws.neon.tech/neondb?sslmode=require&channel_binding=require
   ```
   Cut everything from `?sslmode=...` onward — we handle SSL explicitly in
   `config/runtime.exs` (added below) rather than relying on Ecto to parse
   those query params, which it doesn't reliably do. You should be left
   with:
   ```
   postgresql://user:AbC123@ep-cool-darkness-123456.region.aws.neon.tech/neondb
   ```
   That's your `DATABASE_URL`.

## 2. What changed in the repo for this path

Two small changes, already committed:

- **`config/runtime.exs`**: added an `ECTO_SSL` env var. When set to
  `true`, it adds `ssl: [cacerts: :public_key.cacerts_get()]` to the Repo
  config — required because Neon requires SSL and Postgrex needs it
  explicit, it won't infer it from the URL.
- **`lib/pulse/application.ex`**: added a `RUN_MIGRATIONS_ON_BOOT` env
  var. Render's free tier has no shell or pre-deploy-command access (that
  feature is paid-only), so there's no way to run a one-off
  `bin/pulse eval "Pulse.Release.migrate"` the way we did over SSH on the
  Oracle VM. Instead, when this is set to `true`, the app runs pending
  migrations itself on every boot via the `Ecto.Migrator` child already in
  the supervision tree. This is safe to leave on permanently — Ecto skips
  migrations that already ran, so it's a no-op once the schema's current.

Neither change affects the Oracle/Docker Compose path — both env vars
default to off, so `docker-compose.yml` behaves exactly as before unless
you explicitly set them.

## 3. Create the Render web service

1. Go to render.com → sign up (GitHub OAuth) → no card required.
2. **New** → **Web Service** → connect your GitHub account → select the
   `pulse-zm` repo.
3. Render should detect the `Dockerfile` and offer **Docker** as the
   environment. If it asks for a name, this becomes part of your
   `*.onrender.com` URL — e.g. naming it `pulse-zm` gives you
   `pulse-zm.onrender.com` (Render appends a random suffix if that's
   taken).
4. **Instance Type**: Free.
5. Before the first deploy, add these environment variables (Render
   dashboard → Environment):

   | Key | Value |
   |---|---|
   | `SECRET_KEY_BASE` | generate locally with `mix phx.gen.secret` |
   | `DATABASE_URL` | the stripped Neon connection string from step 1 |
   | `ECTO_SSL` | `true` |
   | `RUN_MIGRATIONS_ON_BOOT` | `true` |
   | `PHX_SERVER` | `true` |
   | `PORT` | `10000` |
   | `PHX_SCHEME` | `https` |
   | `PHX_URL_PORT` | `443` |
   | `PHX_HOST` | *(leave blank for now, see step 6)* |

   Render doesn't read your repo's `.env`/`.env.example` files — these all
   go directly into the dashboard.

6. Deploy. Once it's up, Render shows you the assigned
   `https://<something>.onrender.com` URL — copy the hostname part (no
   `https://`) into `PHX_HOST`, save, and it'll redeploy automatically with
   the correct value. This matters for links Pulse generates (e.g. in
   emails later) pointing to the right place.

## 4. Watch the first deploy

Render's build logs show the same steps you saw locally (deps, assets,
release). First build is typically a few minutes. Once it's live, watch
the runtime logs for the migration output — with `RUN_MIGRATIONS_ON_BOOT`
set, you should see the same `== Running ... forward` / `== Migrated ...`
lines you saw locally, just on boot instead of via a separate command.

## 5. Check it

Visit `https://<your-service>.onrender.com`. First load after any idle
period takes ~1 minute (Render waking the sleeping instance) — that's
expected on the free tier, not a bug.

## 6. Redeploying after code changes

Push to your GitHub repo's default branch — Render auto-deploys on push
by default (toggle-able in settings if you'd rather deploy manually).
Migrations run automatically on boot per step 2, no extra step needed.

## Known follow-ups (same as the Oracle path)

- **Email (Resend)**: still not wired up — separate, already on your
  sprint list.
- **Neon cold starts**: after 5 minutes idle, Neon suspends compute; the
  next query waits a second or two for it to resume. Postgrex's default
  connection-pool pinging can actually prevent this suspend from ever
  kicking in (which is fine — it just means Neon stays "warm," well within
  the 100 CU-hour/month allowance at this traffic level). Not something to
  worry about until usage grows.
- **Backups**: Neon retains a short point-in-time history window on the
  free tier, but nothing is exported off-platform. Worth a periodic
  `pg_dump` once real user data exists, same as noted for the Oracle path.
