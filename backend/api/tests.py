from django.core.management import call_command
from rest_framework.test import APITestCase

from .models import Booking, User

PW = "Maitrio@123"


class FlowTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        call_command("seed", verbosity=0)

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
