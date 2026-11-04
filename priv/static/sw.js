// Pulse's service worker: shows alert notifications and opens the right
// page when one is tapped. The browser runs this in the background, even
// when no Pulse tab is open; the server sends messages to it through the
// browser's push service (see Pulse.Push and Pulse.Alerts).
//
// Each message is JSON: {title, body, url, tag}. A newer message with the
// same tag (same place and utility) replaces the older one instead of
// stacking up.

self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))

self.addEventListener("push", (event) => {
  let data = {}

  try {
    data = event.data ? event.data.json() : {}
  } catch (_error) {
    data = {body: event.data ? event.data.text() : ""}
  }

  const options = {
    body: data.body || "",
    data: {url: data.url || "/"}
  }

  if (data.tag) {
    options.tag = data.tag
    options.renotify = true
  }

  event.waitUntil(self.registration.showNotification(data.title || "Pulse", options))
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()

  const path = (event.notification.data && event.notification.data.url) || "/"
  const url = new URL(path, self.location.origin).href

  event.waitUntil(
    self.clients.matchAll({type: "window", includeUncontrolled: true}).then((windows) => {
      for (const client of windows) {
        if (client.url === url && "focus" in client) return client.focus()
      }

      return self.clients.openWindow(url)
    })
  )
})
