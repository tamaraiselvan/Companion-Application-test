// Background web push. Config lives in firebase-config.js (copy firebase-config.example.js).
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');
importScripts('firebase-config.js');

firebase.initializeApp(self.FIREBASE_CONFIG);
firebase.messaging(); // shows notification payloads automatically while the tab is in the background

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.matchAll({ type: 'window' }).then((list) => list.length ? list[0].focus() : clients.openWindow('/')));
});
