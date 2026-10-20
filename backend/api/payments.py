"""Razorpay integration. Configure RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET.
Without keys, online payments run in mock mode (auto-confirmed) — allowed only when DJANGO_DEBUG is true."""
import base64
import hashlib
import hmac
import json
import os
import urllib.request

from django.conf import settings

API = "https://api.razorpay.com/v1"


def key_id():
    return os.environ.get("RAZORPAY_KEY_ID", "")


def enabled():
    return bool(key_id() and os.environ.get("RAZORPAY_KEY_SECRET"))


def mock_allowed():
    return not enabled() and settings.PAYMENTS_MOCK


def _call(method, path, payload=None):
    auth = base64.b64encode(f"{key_id()}:{os.environ['RAZORPAY_KEY_SECRET']}".encode()).decode()
    req = urllib.request.Request(API + path, method=method, data=json.dumps(payload).encode() if payload else None,
                                 headers={"Authorization": "Basic " + auth, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def create_order(amount_inr, receipt, notes=None):
    return _call("POST", "/orders", {"amount": int(amount_inr) * 100, "currency": "INR", "receipt": receipt,
                                     "notes": notes or {}})


def refund(payment_id, amount_inr):
    return _call("POST", f"/payments/{payment_id}/refund", {"amount": int(amount_inr) * 100})


def _hmac(secret, msg):
    return hmac.new(secret.encode(), msg.encode() if isinstance(msg, str) else msg, hashlib.sha256).hexdigest()


def verify_checkout(order_id, payment_id, signature):
    expected = _hmac(os.environ.get("RAZORPAY_KEY_SECRET", ""), f"{order_id}|{payment_id}")
    return hmac.compare_digest(expected, signature or "")


def verify_webhook(body_bytes, signature):
    secret = os.environ.get("RAZORPAY_WEBHOOK_SECRET", "")
    return bool(secret) and hmac.compare_digest(_hmac(secret, body_bytes), signature or "")
