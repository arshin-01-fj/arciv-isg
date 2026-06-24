self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open('arciv-store').then((cache) => cache.addAll(['index.html', 'form.html', 'admin_panel.html']))
  );
});

self.addEventListener('fetch', (e) => {
  e.respondWith(caches.match(e.request).then((response) => response || fetch(e.request)));
});