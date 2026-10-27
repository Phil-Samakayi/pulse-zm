defmodule Pulse.RateLimit do
  @moduledoc """
  Per-user rate limiting for report/location submissions, backed by
  Hammer's in-memory ETS store (v7 API — see `hit/3,4` calls in
  `Pulse.Reports`).

  ETS means these counters live in this one BEAM node's memory: fine for
  a single-instance deploy (Render, Oracle free tier, Fly single
  machine), but counters reset on every deploy/restart and aren't
  shared across nodes if this is ever scaled horizontally. If that
  changes, swap the backend for `:mnesia` or a Redis-backed one — the
  call sites in `Pulse.Reports` don't need to change either way.
  """

  use Hammer, backend: :ets
end
