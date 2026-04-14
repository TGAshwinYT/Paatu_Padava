const CACHE_NAME = 'paatupadava-v1';

self.addEventListener('install', (event) => {
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil(clients.claim());
});

self.addEventListener('fetch', (event) => {
    // Only intercept GET requests. Let browser handle POST/PUT/DELETE natively.
    if (event.request.method !== 'GET') return;

    event.respondWith(
        fetch(event.request).catch(async () => {
            const cachedResponse = await caches.match(event.request);
            if (cachedResponse) {
                return cachedResponse;
            }
            // Strict Requirement: respondWith MUST return a valid Response object.
            // If offline and uncached, return a generic 503 response instead of undefined.
            return new Response("Network unavailable and resource not cached.", {
                status: 503,
                statusText: "Service Unavailable",
                headers: { "Content-Type": "text/plain" }
            });
        })
    );
});
