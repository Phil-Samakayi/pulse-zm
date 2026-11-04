// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// Show progress bar on live navigation and form submits, in the theme's
// copper rather than topbar's default blue. topbar draws on a <canvas>,
// which can't take a CSS var() directly, so this reads the current
// --copper value and is re-run whenever the theme changes (see
// applyTheme below — dark mode uses a lighter copper).
function configureTopbar() {
  const copper = getComputedStyle(document.documentElement).getPropertyValue("--copper").trim()
  topbar.config({barColors: {0: copper || "#a85c32"}, shadowColor: "rgba(0, 0, 0, .3)"})
}
configureTopbar()
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Page messages ("Welcome back!", "Thanks — your report is in.") from
// CoreComponents.page_flash/1. Rendered outside any LiveView, so this
// plain-JS close works even when the live connection is down. Success
// messages also hide themselves after a few seconds; errors stay until
// closed, so they aren't missed.
document.addEventListener("click", (event) => {
  const close = event.target.closest("[data-flash-close]")
  if (close) close.closest("[data-flash]").remove()
})

document.querySelectorAll('[data-flash="info"]').forEach((el) => {
  setTimeout(() => el.remove(), 6000)
})

// Alerts (push notifications). A "Get alerts" form carries
// data-needs-push: before it's submitted, make sure this browser can
// receive notifications — ask permission, subscribe through the browser's
// push service with Pulse's public key (from the vapid-public-key meta
// tag), and save the subscription to the server. Only then submit the
// form, which records what to alert about. Plain JS and fetch, so it works
// whether or not the page's live connection is up. See Pulse.Alerts.
const vapidPublicKey = document.querySelector("meta[name='vapid-public-key']")?.getAttribute("content")

const pushMessages = {
  unsupported: "This browser can't show alerts. On Android, open Pulse in Chrome.",
  denied: "Notifications are blocked for Pulse. Allow them in your browser's site settings, then try again.",
  failed: "Couldn't turn on alerts just now. Please try again."
}

function urlBase64ToUint8Array(base64) {
  const padding = "=".repeat((4 - (base64.length % 4)) % 4)
  const raw = atob((base64 + padding).replace(/-/g, "+").replace(/_/g, "/"))
  return Uint8Array.from(raw, (char) => char.charCodeAt(0))
}

async function ensurePushSubscription() {
  const supported =
    vapidPublicKey && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window

  if (!supported) throw new Error("unsupported")

  // Ask first, while the tap that triggered this still counts as the
  // user's action — some browsers only show the prompt then.
  const permission =
    Notification.permission === "granted" ? "granted" : await Notification.requestPermission()

  if (permission !== "granted") throw new Error("denied")

  const registration = await navigator.serviceWorker.register("/sw.js")
  await navigator.serviceWorker.ready

  const subscription =
    (await registration.pushManager.getSubscription()) ||
    (await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(vapidPublicKey)
    }))

  const response = await fetch("/alerts/subscriptions", {
    method: "POST",
    headers: {"content-type": "application/json", "x-csrf-token": csrfToken},
    body: JSON.stringify(subscription)
  })

  if (!response.ok) throw new Error("failed")
}

document.addEventListener("submit", async (event) => {
  const form = event.target.closest("form[data-needs-push]")
  if (!form || form.dataset.pushReady === "true") return

  event.preventDefault()
  const status = form.querySelector("[data-push-status]")
  if (status) status.textContent = "Turning on alerts…"

  try {
    await ensurePushSubscription()
    form.dataset.pushReady = "true"
    form.submit()
  } catch (error) {
    // The real reason (a 404 for /sw.js, a push-service refusal, ...) goes
    // to the console; the person just gets the short message.
    console.error("Pulse alerts:", error)
    if (status) status.textContent = pushMessages[error.message] || pushMessages.failed
  }
})

// Theme toggle. Light is the default; dark only applies once someone
// clicks the button, and the choice is remembered in localStorage (the
// inline script in root.html.heex re-applies it on the next visit,
// before the page paints, to avoid a flash of the wrong theme).
//
// The click listener is delegated on `document` rather than attached to
// the button itself, because LiveView can replace that button with a new
// DOM node on live navigation — a direct listener would silently stop
// working after the first page change, but delegation keeps working
// regardless of which node currently sits at #theme-toggle.
function applyTheme(theme) {
  if (theme === "dark") {
    document.documentElement.setAttribute("data-theme", "dark")
  } else {
    document.documentElement.removeAttribute("data-theme")
  }
  configureTopbar()
}

function setTheme(theme) {
  applyTheme(theme)
  try {
    localStorage.setItem("pulse-theme", theme)
  } catch (_error) {
    // localStorage unavailable (private browsing, etc.) — the theme still
    // applies for this page view, it just won't be remembered.
  }
}

document.addEventListener("click", (event) => {
  if (event.target.closest("#theme-toggle")) {
    const isDark = document.documentElement.getAttribute("data-theme") === "dark"
    setTheme(isDark ? "light" : "dark")
  }
})

