# Pulse (Phoenix/LiveView rewrite)

A crowdsourced tracker for power outages, water outages, and market prices
in Zambia, built by and for people who actually deal with load-shedding and
rationing. Anyone can browse a location's current status for free; signing
up lets you submit reports yourself.

This is the second version of Pulse. The first version (Django + DRF API,
React PWA frontend, polling for updates) lives at `../pulse-zm` — kept as
reference/fallback, untouched. This version is a full rewrite in
**Elixir/Phoenix**, chosen specifically so that reports show up **live**
for everyone looking at a location, via Phoenix PubSub, instead of the
React app having to poll or wait for a manual refresh. Same data model,
same business rules (see "What matches the Django version" below), new
language and a materially better live-update story.

## Important: this code has not been compiled or run yet

Everything in this repository was hand-written without ever running
`mix compile` — the sandbox this was built in blocks network access to
`repo.hex.pm` (Elixir's package registry), so `mix deps.get` cannot
resolve Phoenix's dependency tree there. Your machine has normal internet
access, so this isn't a problem for you — it just means **you're the
first compiler this code will see**. There will very likely be small
mistakes (a typo, a missing `alias`, a wrong function arity) that only
show up once the compiler looks at it. That's expected, not a sign
anything is fundamentally wrong — paste me whatever error `mix compile`,
`mix ecto.migrate`, or `mix phx.server` prints and I'll fix it. This is
the same collaborative loop we used for the git/PowerShell issues on the
first version, just starting one step earlier (compile-time instead of
runtime).

## Setup

From inside this folder, in order:

```powershell
mix deps.get
mix setup
```

`mix setup` runs, in order: `deps.get` again (harmless), creates the
SQLite database, runs migrations, seeds demo data, and installs/builds the
frontend assets (Tailwind + esbuild — both download their own prebuilt
binaries the first time, no Node/npm required, unlike the React version).

Then start the server:

```powershell
mix phx.server
```

Visit http://localhost:4000 — you should see the locations list.

If any of these three commands errors out, copy the full terminal output
here and we'll fix it together.

### Demo accounts

Seeded by `priv/repo/seeds.exs` (mirrors the Django seed data exactly —
same Lusaka areas and markets, same illustrative JCTR-sourced prices):

- `demo_resident` / `pulsedemo123`
- `demo_vendor` / `pulsedemo123`

Neither is an admin. To reach `/moderation`, open an `iex -S mix` session
and run:

```elixir
Pulse.Repo.get_by!(Pulse.Accounts.User, username: "demo_resident")
|> Ecto.Changeset.change(is_admin: true)
|> Pulse.Repo.update!()
```

Re-running `mix run priv/repo/seeds.exs` (or `mix ecto.reset`, which wipes
the DB first) is safe — it detects existing demo data and skips instead
of duplicating it.

## What matches the Django version

- Same fields and validation rules for locations, outage reports
  (electricity/water, up/down), and price reports (mealie meal, charcoal,
  kapenta, cooking oil, tomatoes, other — with a required "what is it"
  field when you pick "other").
- Same 2-minute cooldown on submitting a duplicate report (same
  location + utility/commodity + reporter) to cut down on accidental
  double-submits.
- Same community flagging + admin moderation queue for bad reports.
- `reported_at` is always set server-side, never trusted from the client
  — the one exception is the seed script, which backdates timestamps
  directly via `Repo.insert!/1`, bypassing the changeset on purpose (see
  the comment in `priv/repo/seeds.exs`).

## What's new

- **Live updates.** Every `LocationLive.Show` page subscribes to that
  location's PubSub topic. The instant anyone submits or flags a report
  there, every open browser tab showing that page updates — no refresh,
  no polling. This is the main reason for the rewrite.
- SQLite instead of Postgres, to keep setup to one command on Windows.

## What's not done / open questions

- **Offline support.** The React PWA queued reports in `localStorage`
  while offline and replayed them once back online. LiveView needs a live
  socket connection to do anything, so it doesn't have an equivalent out
  of the box — genuine offline support here would mean a client-side JS
  hook doing something similar to the old queue, layered on top of
  LiveView. Worth discussing once the app is up and running, not blocking
  anything today.
- No automated tests were added for the new Reports/Accounts/LiveView
  code (the Django version had none beyond the seed script either, so
  this isn't a regression — just noting it as a gap).
- Production deployment (`mix phx.gen.release`, a real `SECRET_KEY_BASE`,
  etc.) hasn't been set up — this is dev-only for now, same stage the
  Django version was at.

## Project layout

- `lib/pulse/accounts/` — users, session tokens, password hashing. Hand-
  written equivalent of what `mix phx.gen.auth` generates (that generator
  needs a fully compilable project to run, which needs Hex — see above).
- `lib/pulse/reports/` — locations, outage reports, price reports, and
  the PubSub broadcast logic.
- `lib/pulse_web/live/` — the LiveViews: locations list, location detail
  (status + report forms), moderation queue, login/registration.
- `lib/pulse_web/user_auth.ex` — auth plugs (controllers) and `on_mount`
  hooks (LiveViews).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- LiveView docs: https://hexdocs.pm/phoenix_live_view
