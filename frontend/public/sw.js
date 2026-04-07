const CACHE_NAME = 'paatupadava-v1';

self.addEventListener('install', (event) => {
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil(clients.claim());
});

self.addEventListener('fetch', (event) => {
    // Simple pass-through for now, required for PWA installation criteria
    event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
});
