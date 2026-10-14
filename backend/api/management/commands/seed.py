"""Seed demo data mirroring the HTML demo. Usage: python manage.py seed [--password PW]"""
from django.core.management.base import BaseCommand
from django.db import transaction

from api.models import CmsItem, Companion, Coupon, FeatureFlag, Notification, PartnerDoc, Service, User, WalletTx

SERVICES = [
    ("senior", "Senior Maitrion", "🌿", "#7FA69A", ["Walking companion", "Reading", "Shopping", "Hospital visit", "Daily care", "Home conversation"]),
    ("patient", "Patient Maitrion", "🏥", "#E8A33D", ["Hospital assistance", "Doctor consultation", "Medicine collection", "Home recovery support"]),
    ("child", "Child Maitrion", "🎒", "#FF6F5E", ["School pickup", "Homework", "Playtime", "Activity support"]),
    ("travel", "Travel Maitrion", "✈️", "#5B8AA6", ["Airport assistance", "Local guide", "Shopping", "Tourism", "Business meetings"]),
    ("pet", "Pet Maitrion", "🐾", "#9A7FA6", ["Dog walking", "Pet sitting", "Vet visit", "Grooming assistance"]),
    ("event", "Event Maitrion", "🎉", "#C97F3A", ["Weddings", "Conferences", "Family functions", "Business events"]),
    ("shopping", "Shopping Assistant", "🛍️", "#C8657F", ["Grocery run", "Market shopping", "Gift selection", "Returns & exchanges"]),
    ("family", "Family Assistant", "👨‍👩‍👧", "#4E8B7C", ["Household errands", "Appointments & bills", "Elder & child coordination", "Festival prep"]),
    ("railway", "Railway Assistant", "🚆", "#3F6FB5", ["Ticket booking", "PNR & seat help", "Platform assistance", "Luggage & porter"]),
]
NAMES = ["Priya Raman", "Arjun Mehta", "Meena Iyer", "Vikram Rao", "Anjali Nair", "Suresh Pillai", "Divya Krishnan",
         "Rahul Varma", "Kavya Menon", "Joseph D'Souza", "Lakshmi Sundar", "Karthik Subramanian", "Nisha Thomas",
         "Ganesh Babu", "Farah Khan", "Manoj Kumar", "Deepa Nair", "Imran Sheikh"]
COLORS = ["#FF6F5E", "#7FA69A", "#E8A33D", "#5B8AA6", "#9A7FA6", "#C97F3A", "#4E8B7C", "#D9765F"]
LANGS = ["English", "Tamil", "Hindi", "Telugu", "Malayalam"]
DOCS = ["Aadhaar", "PAN", "Police verification", "Certificates", "Profile photo"]


class Command(BaseCommand):
    help = "Seed demo data"

    def add_arguments(self, parser):
        parser.add_argument("--password", default="Maitrio@123")

    @transaction.atomic
    def handle(self, *args, password, **kw):
        svcs = []
        for slug, name, icon, color, sub in SERVICES:
            svc, _ = Service.objects.update_or_create(slug=slug, defaults=dict(name=name, icon=icon, color=color, sub=sub))
            svcs.append(svc)

        def mk(username, first, last="", role="user", **extra):
            u, created = User.objects.get_or_create(username=username, defaults=dict(first_name=first, last_name=last, role=role, **extra))
            if created:
                u.set_password(password)
                u.save()
            return u

        admin = mk("admin", "Admin", role="admin", email="admin@maitrio.app", phone="+919000000001", is_staff=True, is_superuser=True)
        user = mk("+919876543210", "Ananya", "Subramaniam", email="ananya@example.com", phone="+919876543210",
                  address="12, Kasturi Rangan Rd, Chennai", wallet=1250, medical="No known allergies. Mild knee arthritis.")
        if not WalletTx.objects.filter(user=user).exists():
            WalletTx.objects.create(user=user, label="Added money", amount=1000)
            Notification.objects.create(user=user, icon="🎁", title="New offer", body="Get 20% off Senior Maitrion bookings this week.")

        for i, full in enumerate(NAMES):
            first, last = full.split(" ", 1)
            u = mk(f"+91900001{i:04d}", first, last, role="partner", phone=f"+91900001{i:04d}", email=f"partner{i}@maitrio.app")
            svc = svcs[i % len(svcs)]
            c, _ = Companion.objects.get_or_create(user=u, defaults=dict(
                service=svc, gender="Male" if i % 3 == 1 else "Female", age=24 + (i * 3) % 20,
                languages=[LANGS[i % 5], LANGS[(i + 1) % 5]], price=250 + (i % 5) * 70, experience=1 + i % 6,
                distance_km=round(0.6 + i * 0.4, 1), color=COLORS[i % len(COLORS)],
                certs=["ID Verified", "Background Checked"] + (["First Aid Certified"] if i % 2 == 0 else []),
                skills=svc.sub[:3 + i % 2], available=i % 4 != 0,
                status="pending" if i in (2 + 9, 4 + 9) else "active",
                rating=round(3.9 + ((i * 7) % 11) / 10, 1), reviews_count=18 + i * 7,
                bio=f"{first} has {1 + i % 6} yrs of experience in {svc.name.lower()} and is loved by families "
                    f"for being warm, punctual and dependable."))
            for d in DOCS:
                PartnerDoc.objects.get_or_create(companion=c, name=d)

        for code, desc, pct, val, en in [("WELCOME100", "₹100 off your first booking", False, 100, True),
                                         ("SENIOR20", "20% off companion services", True, 20, True),
                                         ("FESTIVE50", "₹50 off festive bookings", False, 50, False)]:
            Coupon.objects.get_or_create(code=code, defaults=dict(desc=desc, percent=pct, value=val, enabled=en))
        if not CmsItem.objects.exists():
            CmsItem.objects.bulk_create([
                CmsItem(kind="banner", title="Festive Care Offer — 20% off"),
                CmsItem(kind="banner", title="New: Pet Maitrion now in Chennai"),
                CmsItem(kind="faq", title="How do I cancel a booking?", body="Go to My Bookings → Upcoming → Cancel."),
                CmsItem(kind="faq", title="How is my companion verified?", body="ID, background and police verification."),
            ])
        for k, en in [("ai_matching", True), ("wallet_cashback", True), ("video_call", False), ("referral", True)]:
            FeatureFlag.objects.get_or_create(key=k, defaults={"enabled": en})

        self.stdout.write(self.style.SUCCESS(
            f"Seeded. Logins (password '{password}'): admin | +919876543210 (user) | +919000010002 (partner Meena Iyer)"))
