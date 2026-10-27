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

