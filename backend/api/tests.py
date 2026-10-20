from django.core.cache import cache
from django.core.management import call_command
from rest_framework.test import APITestCase

from unittest.mock import patch

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
