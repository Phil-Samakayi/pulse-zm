defmodule PulseWeb.Illustrations do
  @moduledoc """
  Small line drawings for the places where Pulse has nothing to show
  yet: no recent prices, no recent report, alerts, no locations.

  Each is an inline SVG of about 1 KB, drawn in `currentColor`, so it takes
  the colour of whatever text class it's given (`text-copper`,
  `text-ink-soft`, …) and follows dark mode with no extra work. Accent
  strokes use the theme's Tailwind colours (`stroke-amber`, `stroke-teal`,
  `stroke-line`), which are CSS variables and flip with the theme too.

  All are decorative (`aria-hidden`); the text next to them says what
  they mean.

      <PulseWeb.Illustrations.basket class="h-16 w-16 text-copper" />
  """

  use Phoenix.Component

  attr :class, :any, default: "h-16 w-16"

  @doc "A market basket with a small plus: no prices yet."
  def basket(assigns) do
    ~H"""
    <svg
      viewBox="0 0 96 96"
      fill="none"
      stroke="currentColor"
      stroke-width="3"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
    >
      <path d="M18 40h60l-7 34a6 6 0 0 1-6 5H31a6 6 0 0 1-6-5z" />
      <path d="M34 40 44 18M62 40 52 18" />
      <path d="M36 52v16M48 52v16M60 52v16" opacity=".55" />
      <circle cx="74" cy="22" r="9" class="fill-amber-bg stroke-amber" />
      <path d="M71 22h6M74 19v6" class="stroke-amber" stroke-width="2.5" />
    </svg>
    """
  end

  attr :class, :any, default: "h-16 w-16"

  @doc "A light bulb with a line through it: no recent report."
  def bulb_off(assigns) do
    ~H"""
    <svg
      viewBox="0 0 96 96"
      fill="none"
      stroke="currentColor"
      stroke-width="3"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
    >
      <path d="M48 14a22 22 0 0 0-13 39.7c2.2 1.7 3.5 4.3 3.5 7.1V64h19v-3.2c0-2.8 1.3-5.4 3.5-7.1A22 22 0 0 0 48 14z" />
      <path d="M39 72h18M42 80h12" />
      <path d="M44 42l4-6 4 6" opacity=".55" />
      <path d="M14 18 82 86" class="stroke-line" stroke-width="4" />
    </svg>
    """
  end

  attr :class, :any, default: "h-16 w-16"

  @doc "A bell with signal waves: alerts."
  def bell(assigns) do
    ~H"""
    <svg
      viewBox="0 0 96 96"
      fill="none"
      stroke="currentColor"
      stroke-width="3"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
    >
      <path d="M30 62V44a18 18 0 0 1 36 0v18l6 8H24z" />
      <path d="M42 76a6 6 0 0 0 12 0" />
      <path d="M18 34a30 30 0 0 1 8-14M78 34a30 30 0 0 0-8-14" class="stroke-teal" />
      <path d="M11 38a38 38 0 0 1 9-22M85 38a38 38 0 0 0-9-22" class="stroke-teal" opacity=".5" />
    </svg>
    """
  end

  attr :class, :any, default: "h-16 w-16"

  @doc "A map pin with a small plus: no places yet."
  def map_pin(assigns) do
    ~H"""
    <svg
      viewBox="0 0 96 96"
      fill="none"
      stroke="currentColor"
      stroke-width="3"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
    >
      <path d="M48 84s24-22 24-44a24 24 0 0 0-48 0c0 22 24 44 24 44z" />
      <circle cx="48" cy="40" r="8" />
      <path d="M70 70h14M77 63v14" class="stroke-teal" />
    </svg>
    """
  end
end
