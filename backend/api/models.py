import secrets
from decimal import Decimal

from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    ROLES = [("user", "User"), ("partner", "Partner"), ("admin", "Admin")]
    role = models.CharField(max_length=10, choices=ROLES, default="user")
    phone = models.CharField(max_length=20, unique=True, null=True, blank=True)
    address = models.CharField(max_length=255, blank=True)
    language = models.CharField(max_length=20, default="English")
    medical = models.TextField(blank=True)
    emergency_contact = models.CharField(max_length=120, blank=True)
    wallet = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0"))
    favorites = models.ManyToManyField("Companion", blank=True, related_name="fans")
    # Per-category push/in-app notification opt-outs, e.g. {"offers": false}. Missing key = enabled.
    notif_prefs = models.JSONField(default=dict, blank=True)

    @property
    def is_admin_role(self):
        return self.role == "admin" or self.is_superuser


class Service(models.Model):
    slug = models.SlugField(unique=True)
    name = models.CharField(max_length=60)
    icon = models.CharField(max_length=8)
    color = models.CharField(max_length=9)
    sub = models.JSONField(default=list)

    def __str__(self):
        return self.name


class Companion(models.Model):
    STATUS = [("pending", "Pending"), ("active", "Active"), ("rejected", "Rejected")]
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="companion")
    service = models.ForeignKey(Service, on_delete=models.PROTECT, related_name="companions")
    gender = models.CharField(max_length=10)
    age = models.PositiveSmallIntegerField(default=25)
    languages = models.JSONField(default=list)
    price = models.PositiveIntegerField(help_text="INR per hour")
    experience = models.PositiveSmallIntegerField(default=1)
    distance_km = models.FloatField(default=1.0, help_text="Fallback when the client sends no location")
    lat = models.FloatField(null=True, blank=True, help_text="Base location")
    lng = models.FloatField(null=True, blank=True)
    bio = models.TextField(blank=True)
    skills = models.JSONField(default=list)
    certs = models.JSONField(default=list)
    color = models.CharField(max_length=9, default="#FF6F5E")
    available = models.BooleanField(default=True)
    status = models.CharField(max_length=10, choices=STATUS, default="pending")
    rating = models.FloatField(default=0)
    reviews_count = models.PositiveIntegerField(default=0)

    def __str__(self):
        return self.user.get_full_name() or self.user.username


def booking_code():
    return "CMP-" + secrets.token_hex(3).upper()


class Booking(models.Model):
    STATUS = [(s, s.replace("_", " ").title()) for s in
              ("awaiting_payment", "pending", "accepted", "in_progress", "completed", "cancelled", "rejected")]
    PAYMENTS = [(p, p) for p in ("UPI", "Card", "Net Banking", "Wallet", "Cash")]
    code = models.CharField(max_length=12, unique=True, default=booking_code)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="bookings")
    companion = models.ForeignKey(Companion, on_delete=models.PROTECT, related_name="bookings")
    date = models.DateField()
    time = models.TimeField()
    duration = models.PositiveSmallIntegerField(default=1)
    address = models.CharField(max_length=255)
    instructions = models.TextField(blank=True)
    payment = models.CharField(max_length=20, choices=PAYMENTS, default="UPI")
    PAY_STATUS = [(s, s.title()) for s in ("unpaid", "paid", "cash", "refunded")]
    payment_status = models.CharField(max_length=10, choices=PAY_STATUS, default="unpaid")
    coupon = models.CharField(max_length=30, blank=True)
    subtotal = models.PositiveIntegerField(default=0)
    discount = models.PositiveIntegerField(default=0)
    price = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=20, choices=STATUS, default="pending")
    checked_in_at = models.DateTimeField(null=True, blank=True)
    checked_out_at = models.DateTimeField(null=True, blank=True)
    dest_lat = models.FloatField(null=True, blank=True, help_text="Service address location")
    dest_lng = models.FloatField(null=True, blank=True)
    lat = models.FloatField(null=True, blank=True, help_text="Companion live location")
    lng = models.FloatField(null=True, blank=True)
    location_at = models.DateTimeField(null=True, blank=True)
    arrival_notified = models.BooleanField(default=False)
    created = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created"]


class Device(models.Model):
    """Push token (FCM) for a user's phone or browser."""
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="devices")
    token = models.CharField(max_length=512, unique=True)
    platform = models.CharField(max_length=10, choices=[(p, p) for p in ("android", "ios", "web")])
    updated = models.DateTimeField(auto_now=True)


class Review(models.Model):
    booking = models.OneToOneField(Booking, on_delete=models.CASCADE, related_name="review")
    stars = models.PositiveSmallIntegerField()
    text = models.TextField(blank=True)
    created = models.DateTimeField(auto_now_add=True)


class WalletTx(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="wallet_tx")
    label = models.CharField(max_length=120)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    created = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created"]


class Notification(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="notifications")
    icon = models.CharField(max_length=8, default="🔔")
    category = models.CharField(max_length=12, default="booking")
    title = models.CharField(max_length=120)
    body = models.TextField()
    unread = models.BooleanField(default=True)
    created = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created"]


class Coupon(models.Model):
    code = models.CharField(max_length=30, unique=True)
    desc = models.CharField(max_length=160)
    percent = models.BooleanField(default=False, help_text="True: value is %, False: flat INR")
    value = models.PositiveIntegerField()
    enabled = models.BooleanField(default=True)

    def discount_for(self, subtotal):
        d = subtotal * self.value // 100 if self.percent else self.value
        return min(d, subtotal)


class ChatMessage(models.Model):
    sender = models.ForeignKey(User, on_delete=models.CASCADE, related_name="sent_messages")
    receiver = models.ForeignKey(User, on_delete=models.CASCADE, related_name="received_messages")
    text = models.TextField(max_length=2000)
    read = models.BooleanField(default=False)
    created = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created"]


class PartnerDoc(models.Model):
    companion = models.ForeignKey(Companion, on_delete=models.CASCADE, related_name="docs")
    name = models.CharField(max_length=60)
    file = models.FileField(upload_to="docs/", blank=True)
    verified = models.BooleanField(default=False)

    class Meta:
        unique_together = ("companion", "name")


class SOSAlert(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="sos_alerts")
    booking = models.ForeignKey(Booking, null=True, blank=True, on_delete=models.SET_NULL)
    lat = models.FloatField(null=True, blank=True)
    lng = models.FloatField(null=True, blank=True)
    resolved = models.BooleanField(default=False)
    created = models.DateTimeField(auto_now_add=True)


class CmsItem(models.Model):
    kind = models.CharField(max_length=10, choices=[("banner", "Banner"), ("faq", "FAQ")])
    title = models.CharField(max_length=200)
    body = models.TextField(blank=True)


class FeatureFlag(models.Model):
    key = models.CharField(max_length=60, unique=True)
    enabled = models.BooleanField(default=False)


class OtpCode(models.Model):
    """One-time login code. Only an HMAC of the code is stored."""
    phone = models.CharField(max_length=20, db_index=True)
    code_hash = models.CharField(max_length=64)
    expires = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    used = models.BooleanField(default=False)
    created = models.DateTimeField(auto_now_add=True)


class Payment(models.Model):
    """A Razorpay order for a booking or a wallet top-up."""
    PURPOSE = [("booking", "Booking"), ("topup", "Wallet top-up")]
    STATUS = [(s, s.title()) for s in ("created", "paid", "failed", "refunded")]
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="payments")
    purpose = models.CharField(max_length=10, choices=PURPOSE)
    booking = models.ForeignKey(Booking, null=True, blank=True, on_delete=models.SET_NULL, related_name="payments")
    amount = models.PositiveIntegerField(help_text="INR")
    order_id = models.CharField(max_length=64, unique=True)
    payment_id = models.CharField(max_length=64, blank=True)
    status = models.CharField(max_length=10, choices=STATUS, default="created")
    created = models.DateTimeField(auto_now_add=True)
