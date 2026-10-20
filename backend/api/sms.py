"""SMS delivery for login OTPs. SMS_PROVIDER: msg91 | twilio | console (default, logs only — dev)."""
import base64
import json
import logging
import os
import urllib.parse
import urllib.request

log = logging.getLogger(__name__)


def _post(url, data, headers):
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.status


def send_otp(phone, code):
    provider = os.environ.get("SMS_PROVIDER", "console")
    if provider == "msg91":
        # MSG91 OTP API with a DLT-approved template containing ##OTP##
        body = json.dumps({"template_id": os.environ["MSG91_TEMPLATE_ID"], "mobile": phone.lstrip("+"), "otp": code}).encode()
        return _post("https://control.msg91.com/api/v5/otp", body,
                     {"authkey": os.environ["MSG91_AUTH_KEY"], "Content-Type": "application/json"})
    if provider == "twilio":
        sid, token = os.environ["TWILIO_ACCOUNT_SID"], os.environ["TWILIO_AUTH_TOKEN"]
        body = urllib.parse.urlencode({"To": phone, "From": os.environ["TWILIO_FROM"],
                                       "Body": f"{code} is your dayfello login code. It expires in 5 minutes."}).encode()
        auth = base64.b64encode(f"{sid}:{token}".encode()).decode()
        return _post(f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json", body,
                     {"Authorization": "Basic " + auth, "Content-Type": "application/x-www-form-urlencoded"})
    log.warning("SMS_PROVIDER=console: OTP for %s is %s", phone, code)
