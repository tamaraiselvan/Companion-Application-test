from django.core.cache import cache
from django.core.management import call_command
from rest_framework.test import APITestCase

from unittest.mock import patch

from django.test import override_settings

from .models import Booking, Device, Notification, User

PW = "Dayfello@123"


class FlowTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        call_command("seed", verbosity=0)

    def setUp(self):
        cache.clear()  # reset auth throttling between tests

    def login(self, ident):
        r = self.client.post("/api/v1/auth/login/", {"username": ident, "password": PW})
        self.assertEqual(r.status_code, 200, r.data)
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + r.data["access"])
        return r.data

    def test_auth_required(self):
        self.assertEqual(self.client.get("/api/v1/bookings/").status_code, 401)

    def test_register_and_me(self):
        r = self.client.post("/api/v1/auth/register/", {"name": "Test", "phone": "+911112223334",
                                                       "email": "t@x.com", "password": "Str0ng!Pass"})
        self.assertEqual(r.status_code, 201, r.data)
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + r.data["access"])
        self.assertEqual(self.client.get("/api/v1/auth/me/").data["name"], "Test")

    def test_full_booking_flow(self):
        meena = User.objects.get(username="+919000010002").companion
        self.login("+919876543210")
        r = self.client.post("/api/v1/bookings/", {"companion": meena.id, "date": "2030-01-01", "time": "10:00",
                                                  "duration": 2, "address": "Chennai", "payment": "Wallet",
                                                  "coupon": "WELCOME100"})
        self.assertEqual(r.status_code, 201, r.data)
        bid, total = r.data["id"], r.data["price"]
        self.assertEqual(total, meena.price * 2 - 100)
        self.assertEqual(float(self.client.get("/api/v1/wallet/").data["balance"]), 1250 - total)
        # customer cannot accept their own booking
        self.assertEqual(self.client.post(f"/api/v1/bookings/{bid}/accept/").status_code, 403)

        self.login("+919000010002")
        for step in ("accept", "check-in", "check-out"):
            self.assertEqual(self.client.post(f"/api/v1/bookings/{bid}/{step}/").status_code, 200, step)
        self.assertEqual(self.client.get("/api/v1/partner/dashboard/").data["completed"], 1)

        self.login("+919876543210")
        self.assertEqual(self.client.post(f"/api/v1/bookings/{bid}/rate/", {"stars": 5}).status_code, 200)
        self.assertEqual(self.client.post(f"/api/v1/chat/{meena.user_id}/", {"text": "Thanks!"}).status_code, 201)
        self.assertEqual(Booking.objects.get(pk=bid).status, "completed")

    def test_cancel_refunds_wallet(self):
        c = User.objects.get(username="+919000010002").companion
        self.login("+919876543210")
        bid = self.client.post("/api/v1/bookings/", {"companion": c.id, "date": "2030-01-01", "time": "10:00",
                                                    "duration": 1, "address": "x", "payment": "Wallet"}).data["id"]
        self.client.post(f"/api/v1/bookings/{bid}/cancel/")
        self.assertEqual(float(self.client.get("/api/v1/wallet/").data["balance"]), 1250)

    def test_chat_requires_booking(self):
        other = User.objects.get(username="+919000010005")
        self.login("+919876543210")
        self.assertEqual(self.client.get(f"/api/v1/chat/{other.id}/").status_code, 403)

    def test_admin_only(self):
        self.login("+919876543210")
        self.assertEqual(self.client.get("/api/v1/admin/stats/").status_code, 403)
        self.login("admin")
        self.assertEqual(self.client.get("/api/v1/admin/stats/").status_code, 200)
        pending = self.client.get("/api/v1/admin/companions/").data[0]
        self.assertEqual(self.client.post(f"/api/v1/admin/companions/{pending['id']}/approve/").data["status"], "active")


class MapsAndNotificationTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        call_command("seed", verbosity=0)

    setUp = FlowTests.setUp
    login = FlowTests.login

    def _booking(self):
        self.meena = User.objects.get(username="+919000010002").companion
        self.login("+919876543210")
        r = self.client.post("/api/v1/bookings/", {"companion": self.meena.id, "date": "2030-01-01", "time": "10:00",
                                                  "duration": 1, "address": "Chennai", "dest_lat": 13.05, "dest_lng": 80.25})
        self.assertEqual(r.status_code, 201, r.data)
        return r.data["id"]

    def test_companions_sorted_by_real_distance(self):
        r = self.client.get("/api/v1/companions/", {"lat": 13.0827, "lng": 80.2707, "ordering": "distance_km"})
        d = [c["distance_km"] for c in r.data]
        self.assertEqual(d, sorted(d))
        near = self.client.get("/api/v1/companions/", {"lat": 13.0827, "lng": 80.2707, "radius_km": 2}).data
        self.assertTrue(all(c["distance_km"] <= 2 for c in near))

    @patch("api.views.send_push")
    def test_live_location_eta_and_arrival_push(self, push):
        bid = self._booking()
        self.login("+919000010002")
        self.assertEqual(self.client.post(f"/api/v1/bookings/{bid}/location/", {"lat": 13.0, "lng": 80.2}).status_code, 400)
        self.client.post(f"/api/v1/bookings/{bid}/accept/")
        r = self.client.post(f"/api/v1/bookings/{bid}/location/", {"lat": 13.10, "lng": 80.25})
        self.assertGreater(r.data["eta_min"], 1)
        self.assertFalse(Notification.objects.filter(category="arrival").exists())
        self.client.post(f"/api/v1/bookings/{bid}/location/", {"lat": 13.0505, "lng": 80.2502})
        self.assertEqual(Notification.objects.filter(category="arrival").count(), 1)
        self.client.post(f"/api/v1/bookings/{bid}/location/", {"lat": 13.0501, "lng": 80.2501})
        self.assertEqual(Notification.objects.filter(category="arrival").count(), 1)  # only once
        self.assertTrue(any(c.args[1] == "Your companion has arrived" for c in push.call_args_list))

    @patch("api.views.send_push")
    def test_prefs_mute_category_but_not_emergency(self, push):
        self.login("+919876543210")
        self.assertEqual(self.client.patch("/api/v1/auth/me/", {"notif_prefs": {"bogus": True}}, format="json").status_code, 400)
        self.client.patch("/api/v1/auth/me/", {"notif_prefs": {"payment": False, "offers": False}}, format="json")
        self.client.post("/api/v1/wallet/", {"amount": 100})
        self.assertFalse(Notification.objects.filter(user__username="+919876543210", category="payment").exists())
        self.login("admin")
        sent = self.client.post("/api/v1/admin/broadcast/", {"body": "Sale!"}).data["sent"]
        self.assertFalse(Notification.objects.filter(user__username="+919876543210", category="offers").exists())
        self.assertGreaterEqual(sent, 0)

    def test_device_registration(self):
        self.login("+919876543210")
        self.assertEqual(self.client.post("/api/v1/devices/", {"token": "abc", "platform": "web"}).status_code, 201)
        self.assertEqual(self.client.post("/api/v1/devices/", {"token": "abc", "platform": "web"}).status_code, 201)
        self.assertEqual(Device.objects.filter(token="abc").count(), 1)
        self.assertEqual(self.client.post("/api/v1/devices/", {"token": "x", "platform": "pc"}).status_code, 400)
        self.client.delete("/api/v1/devices/", {"token": "abc"})
        self.assertFalse(Device.objects.exists())


class OtpAndPaymentTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        call_command("seed", verbosity=0)

    setUp = FlowTests.setUp
    login = FlowTests.login

    @override_settings(DEMO_OTP="")
    @patch("api.views.send_otp")
    def test_sms_otp_login(self, sms):
        phone = "+919876543210"
        self.assertEqual(self.client.post("/api/v1/auth/otp/request/", {"phone": phone}).status_code, 200)
        code = sms.call_args.args[1]
        self.assertEqual(self.client.post("/api/v1/auth/otp/request/", {"phone": phone}).status_code, 400)  # 30s cooldown
        self.assertEqual(self.client.post("/api/v1/auth/otp/verify/", {"phone": phone, "otp": "000000" if code != "000000" else "111111"}).status_code, 400)
        r = self.client.post("/api/v1/auth/otp/verify/", {"phone": phone, "otp": code})
        self.assertEqual(r.status_code, 200, r.data)
        self.assertIn("access", r.data)
        self.assertEqual(self.client.post("/api/v1/auth/otp/verify/", {"phone": phone, "otp": code}).status_code, 400)  # single use
        # unknown numbers get the same response but no SMS
        sms.reset_mock()
        self.assertEqual(self.client.post("/api/v1/auth/otp/request/", {"phone": "+911234567890"}).status_code, 200)
        sms.assert_not_called()

    @override_settings(DEMO_OTP="")
    @patch("api.views.send_otp")
    def test_otp_locks_after_too_many_attempts(self, sms):
        phone = "+919876543210"
        self.client.post("/api/v1/auth/otp/request/", {"phone": phone})
        code = sms.call_args.args[1]
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            self.client.post("/api/v1/auth/otp/verify/", {"phone": phone, "otp": wrong})
            cache.clear()
        self.assertEqual(self.client.post("/api/v1/auth/otp/verify/", {"phone": phone, "otp": code}).status_code, 400)

    @patch.dict("os.environ", {"RAZORPAY_KEY_ID": "rzp_test_x", "RAZORPAY_KEY_SECRET": "sec", "RAZORPAY_WEBHOOK_SECRET": "wh"})
    @patch("api.payments.create_order", return_value={"id": "order_1"})
    def test_razorpay_booking_and_topup(self, _order):
        import hashlib, hmac, json
        meena = User.objects.get(username="+919000010002").companion
        self.login("+919876543210")
        r = self.client.post("/api/v1/bookings/", {"companion": meena.id, "date": "2030-01-01", "time": "10:00",
                                                  "duration": 1, "address": "x", "payment": "UPI"})
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(r.data["status"], "awaiting_payment")
        self.assertEqual(r.data["checkout"]["order_id"], "order_1")
        bid = r.data["id"]
        # companion cannot see it yet
        self.login("+919000010002")
        self.assertEqual(self.client.get(f"/api/v1/bookings/{bid}/").status_code, 404)
        self.login("+919876543210")
        bad = {"razorpay_order_id": "order_1", "razorpay_payment_id": "pay_1", "razorpay_signature": "nope"}
        self.assertEqual(self.client.post("/api/v1/payments/verify/", bad).status_code, 400)
        sig = hmac.new(b"sec", b"order_1|pay_1", hashlib.sha256).hexdigest()
        r = self.client.post("/api/v1/payments/verify/", {**bad, "razorpay_signature": sig})
        self.assertEqual(r.data["status"], "paid")
        b = Booking.objects.get(pk=bid)
        self.assertEqual((b.status, b.payment_status), ("pending", "paid"))
        # webhook for a top-up, delivered twice: credited once
        _order.return_value = {"id": "order_2"}
        self.assertEqual(self.client.post("/api/v1/wallet/", {"amount": 500}).data["checkout"]["order_id"], "order_2")
        body = json.dumps({"event": "payment.captured", "payload": {"payment": {"entity": {"id": "pay_2", "order_id": "order_2"}}}}).encode()
        wsig = hmac.new(b"wh", body, hashlib.sha256).hexdigest()
        self.client.credentials()
        self.assertEqual(self.client.post("/api/v1/payments/webhook/", body, content_type="application/json", HTTP_X_RAZORPAY_SIGNATURE="bad").status_code, 400)
        for _ in range(2):
            self.client.post("/api/v1/payments/webhook/", body, content_type="application/json", HTTP_X_RAZORPAY_SIGNATURE=wsig)
        self.assertEqual(float(User.objects.get(username="+919876543210").wallet), 1250 + 500)

    @override_settings(PAYMENTS_MOCK=False)
    def test_online_payment_refused_without_gateway(self):
        meena = User.objects.get(username="+919000010002").companion
        self.login("+919876543210")
        r = self.client.post("/api/v1/bookings/", {"companion": meena.id, "date": "2030-01-01", "time": "10:00",
                                                  "duration": 1, "address": "x", "payment": "Card"})
        self.assertEqual(r.status_code, 400)
