const CACHE = 'tripsync-shell-v2';

const APP_SHELL = [
  '/',
  '/index.html',
  '/manifest.webmanifest'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(APP_SHELL))
      .catch(() => undefined)
      .finally(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(key => key !== CACHE)
          .map(key => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const req = event.request;

  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  if (url.origin !== self.location.origin) return;

  // Don't intercept the service worker itself
  if (url.pathname === '/sw.js') return;

  event.respondWith(
    fetch(req)
      .then(response => {

        // Keep the main PWA shell updated in cache
        if (
          response &&
          response.ok &&
          (
            url.pathname === '/' ||
            url.pathname === '/index.html' ||
            url.pathname === '/manifest.webmanifest'
          )
        ) {
          const copy = response.clone();

          caches
            .open(CACHE)
            .then(cache => cache.put(req, copy))
            .catch(() => undefined);
        }

        return response;
      })
      .catch(() =>
        caches.match(req).then(
          cached => cached || caches.match('/index.html')
        )
      )
  );
});


// ========================================
// TRIPSYNC WEB PUSH
// ========================================

self.addEventListener('push', event => {
  let data = {};

  try {
    data = event.data
      ? event.data.json()
      : {};
  } catch (_) {
    data = {};
  }

  const title = String(
    data.title || 'TripSync'
  );

  const options = {
    body: String(
      data.body ||
      'There is new activity on your trip.'
    ),

    icon: data.icon || '/icon.svg',

    badge: data.badge || '/icon.svg',

    tag: String(
      data.tag || 'tripsync'
    ),

    renotify: true,

    data: {
      url: data.url || '/'
    }
  };

  event.waitUntil(
    self.registration.showNotification(
      title,
      options
    )
  );
});


// ========================================
// NOTIFICATION CLICK
// ========================================

self.addEventListener('notificationclick', event => {
  event.notification.close();

  const target =
    event.notification.data?.url || '/';

  event.waitUntil(
    clients
      .matchAll({
        type: 'window',
        includeUncontrolled: true
      })
      .then(list => {

        const sameOrigin = list.find(
          client =>
            new URL(client.url).origin ===
            self.location.origin
        );

        if (sameOrigin) {
          return sameOrigin
            .navigate(target)
            .then(() => sameOrigin.focus());
        }

        return clients.openWindow(target);
      })
  );
});
