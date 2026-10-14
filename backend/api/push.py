"""Firebase Cloud Messaging delivery. Disabled (no-op) unless FIREBASE_CREDENTIALS is set to a
service-account JSON file path or the JSON itself."""
import json
import logging
import os
import threading

from django.db import transaction

log = logging.getLogger(__name__)
_app = None
_lock = threading.Lock()


def _firebase():
    global _app
    creds = os.environ.get("FIREBASE_CREDENTIALS")
    if not creds:
        return None
    with _lock:
        if _app is None:
            import firebase_admin
            from firebase_admin import credentials
            info = json.loads(creds) if creds.strip().startswith("{") else creds
            _app = firebase_admin.initialize_app(credentials.Certificate(info))
    return _app


def _send(tokens, title, body, data):
    try:
        app = _firebase()
        if not app or not tokens:
            return
        from firebase_admin import messaging
        msg = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(priority="high", notification=messaging.AndroidNotification(channel_id="maitrio")),
            apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(sound="default"))),
        )
        res = messaging.send_each_for_multicast(msg, app=app)
        dead = [tokens[i] for i, r in enumerate(res.responses)
                if not r.success and type(r.exception).__name__ in ("UnregisteredError", "SenderIdMismatchError")]
        if dead:
            from .models import Device
            Device.objects.filter(token__in=dead).delete()
    except Exception:  # never let push failures break the API request
        log.exception("FCM push failed")


def send_push(users, title, body, data=None):
    """Queue a push to all devices of `users` after the current DB transaction commits."""
    from .models import Device
    ids = [u.pk for u in users]

    def run():
        tokens = list(Device.objects.filter(user_id__in=ids).values_list("token", flat=True))
        if tokens and os.environ.get("FIREBASE_CREDENTIALS"):
            threading.Thread(target=_send, args=(tokens, title, body, data), daemon=True).start()
    transaction.on_commit(run)
