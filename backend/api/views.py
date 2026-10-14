from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.db.models import Avg, Count, F, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, mixins, permissions, status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView

from . import serializers as s
from .geo import ARRIVAL_RADIUS_KM, haversine_km
from .push import send_push
from .models import (Booking, ChatMessage, CmsItem, Companion, Coupon, Device, FeatureFlag, Notification,
                     PartnerDoc, Review, Service, SOSAlert, User, WalletTx)


# ---------- permissions ----------
class IsAdminRole(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.is_admin_role)


class IsPartner(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and hasattr(request.user, "companion"))


NOTIF_CATEGORIES = ("booking", "arrival", "payment", "offers", "emergency")


def notify(user, title, body, icon="🔔", category="booking", **data):
    """In-app notification + push, honouring the user's per-category opt-outs (emergency can't be muted)."""
    if category != "emergency" and (user.notif_prefs or {}).get(category) is False:
        return
    Notification.objects.create(user=user, title=title, body=body, icon=icon, category=category)
    send_push([user], title, body, {"category": category, **data})


def tokens_for(user):
    r = RefreshToken.for_user(user)
    return {"access": str(r.access_token), "refresh": str(r), "user": s.UserSerializer(user).data}


# ---------- auth ----------
class LoginView(TokenObtainPairView):
    """POST {username, password} -> {access, refresh}. username may be phone or email."""
    permission_classes = [permissions.AllowAny]
    throttle_scope = "auth"

    def post(self, request, *args, **kwargs):
        ident = request.data.get("username", "")
        u = User.objects.filter(Q(phone=ident) | Q(email__iexact=ident) | Q(username=ident)).first()
        data = {"username": u.username if u else ident, "password": request.data.get("password", "")}
        ser = self.get_serializer(data=data)
        ser.is_valid(raise_exception=True)
        return Response({**ser.validated_data, "user": s.UserSerializer(ser.user).data})


class OtpVerifyView(APIView):
    """Phone + OTP login. Integrate an SMS provider here; DEMO_OTP is accepted when configured."""
    permission_classes = [permissions.AllowAny]
    throttle_scope = "auth"

    def post(self, request):
        phone, otp = request.data.get("phone", ""), request.data.get("otp", "")
        if not settings.DEMO_OTP or otp != settings.DEMO_OTP:
            raise ValidationError({"otp": "Invalid OTP"})
        user = User.objects.filter(phone=phone, is_active=True).first()
        if not user:
            raise ValidationError({"phone": "No account for this number"})
        return Response(tokens_for(user))


class RegisterView(generics.CreateAPIView):
    permission_classes = [permissions.AllowAny]
    serializer_class = s.RegisterSerializer
    throttle_scope = "auth"

    def create(self, request, *args, **kwargs):
        ser = self.get_serializer(data=request.data)
        ser.is_valid(raise_exception=True)
        user = ser.save()
        notify(user, "Welcome to Maitrio", "Your account is ready. Book your first companion!", "🎉")
        return Response(tokens_for(user), status=status.HTTP_201_CREATED)


class MeView(generics.RetrieveUpdateAPIView):
    serializer_class = s.UserSerializer

    def get_object(self):
        return self.request.user


@api_view(["POST"])
def change_password(request):
    u = request.user
    if not u.check_password(request.data.get("old_password", "")):
        raise ValidationError({"old_password": "Incorrect password"})
    from django.contrib.auth.password_validation import validate_password
    validate_password(request.data.get("new_password", ""), u)
    u.set_password(request.data["new_password"])
    u.save()
    return Response({"ok": True})


# ---------- catalogue ----------
class ServiceViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Service.objects.all().order_by("id")
    serializer_class = s.ServiceSerializer
    permission_classes = [permissions.AllowAny]


class CompanionViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = s.CompanionSerializer
    permission_classes = [permissions.AllowAny]

    def get_queryset(self):
        qs = Companion.objects.filter(status="active").select_related("user", "service")
        p = self.request.query_params
        if p.get("service"):
            qs = qs.filter(service__slug=p["service"])
        if p.get("gender"):
            qs = qs.filter(gender=p["gender"])
        if p.get("min_rating"):
            qs = qs.filter(rating__gte=float(p["min_rating"]))
        if p.get("max_price"):
            qs = qs.filter(price__lte=int(p["max_price"]))
        if p.get("available") == "true":
            qs = qs.filter(available=True)
        if p.get("q"):
            qs = qs.filter(Q(user__first_name__icontains=p["q"]) | Q(user__last_name__icontains=p["q"])
                           | Q(service__name__icontains=p["q"]))
        if p.get("language"):  # JSON list contains, portable across sqlite/postgres
            qs = [c for c in qs if p["language"] in c.languages]
        order = p.get("ordering")
        try:
            lat, lng = float(p["lat"]), float(p["lng"])
        except (KeyError, ValueError):
            lat = lng = None
        if lat is not None:  # real distance from the user's location
            qs = list(qs)
            for c in qs:
                if c.lat is not None:
                    c.distance_km = round(haversine_km(lat, lng, c.lat, c.lng), 1)
            if p.get("radius_km"):
                qs = [c for c in qs if c.distance_km <= float(p["radius_km"])]
        if order in ("distance_km", "-rating", "price"):
            key, rev = order.lstrip("-"), order.startswith("-")
            qs = sorted(qs, key=lambda c: getattr(c, key), reverse=rev) if isinstance(qs, list) else qs.order_by(order)
        return qs

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "detail": self.action == "retrieve"}

    @action(detail=False, permission_classes=[permissions.IsAuthenticated])
    def favorites(self, request):
        return Response(s.CompanionSerializer(request.user.favorites.all(), many=True).data)

    @action(detail=True, methods=["post"], permission_classes=[permissions.IsAuthenticated])
    def favorite(self, request, pk=None):
        c = self.get_object()
        if request.user.favorites.filter(pk=c.pk).exists():
            request.user.favorites.remove(c)
            return Response({"favorite": False})
        request.user.favorites.add(c)
        return Response({"favorite": True})


# ---------- bookings ----------
class BookingViewSet(mixins.CreateModelMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin,
                     viewsets.GenericViewSet):
    serializer_class = s.BookingSerializer

    def get_queryset(self):
        u = self.request.user
        qs = Booking.objects.select_related("companion__user", "companion__service", "user")
        if u.is_admin_role:
            pass
        elif hasattr(u, "companion") and self.request.query_params.get("as") == "partner":
            qs = qs.filter(companion=u.companion)
        else:
            qs = qs.filter(Q(user=u) | Q(companion__user=u))
        st = self.request.query_params.get("status")
        if st:
            qs = qs.filter(status__in=st.split(","))
        return qs

    @transaction.atomic
    def perform_create(self, ser):
        user = User.objects.select_for_update().get(pk=self.request.user.pk)
        comp = ser.validated_data["companion"]
        subtotal = comp.price * ser.validated_data["duration"]
        discount, code = 0, ser.validated_data.get("coupon", "").strip().upper()
        if code:
            cp = Coupon.objects.filter(code=code, enabled=True).first()
            if not cp:
                raise ValidationError({"coupon": "Invalid or expired coupon"})
            discount = cp.discount_for(subtotal)
        total = subtotal - discount
        if ser.validated_data.get("payment") == "Wallet":
            if user.wallet < total:
                raise ValidationError({"payment": "Insufficient wallet balance"})
            user.wallet -= Decimal(total)
            user.save(update_fields=["wallet"])
            WalletTx.objects.create(user=user, label=f"Booking — {comp}", amount=-total)
        b = ser.save(user=user, coupon=code, subtotal=subtotal, discount=discount, price=total)
        notify(user, "Booking placed", f"Your booking {b.code} with {comp} is awaiting confirmation.", "🕒", booking_id=b.id)
        notify(comp.user, "New job request", f"{user.first_name} requested {comp.service.name} on {b.date}.", "🧾",
               booking_id=b.id)

    def _transition(self, allowed_from, to, by_partner=None):
        b = self.get_object()
        u = self.request.user
        is_partner, is_user = b.companion.user_id == u.id, b.user_id == u.id
        if by_partner is True and not is_partner:
            raise PermissionDenied("Only the assigned companion can do this.")
        if by_partner is False and not is_user:
            raise PermissionDenied("Only the customer can do this.")
        if b.status not in allowed_from:
            raise ValidationError({"status": f"Cannot change booking from {b.status} to {to}."})
        b.status = to
        return b

    def _refund(self, b):
        if b.payment == "Wallet" and b.price:
            User.objects.filter(pk=b.user_id).update(wallet=F("wallet") + b.price)
            WalletTx.objects.create(user=b.user, label=f"Refund — {b.code}", amount=b.price)
            notify(b.user, "Refund processed", f"{inr(b.price)} for {b.code} was returned to your wallet.", "💳", "payment")

    @action(detail=True, methods=["post"])
    @transaction.atomic
    def cancel(self, request, pk=None):
        b = self._transition(["pending", "accepted"], "cancelled", by_partner=False)
        b.save()
        self._refund(b)
        notify(b.companion.user, "Booking cancelled", f"{b.code} was cancelled by the customer.", "❌", booking_id=b.id)
        return Response(self.get_serializer(b).data)

    @action(detail=True, methods=["post"])
    def accept(self, request, pk=None):
        b = self._transition(["pending"], "accepted", by_partner=True)
        b.save()
        notify(b.user, "Booking confirmed", f"{b.companion} accepted {b.code} for {b.date}, {b.time:%H:%M}.", "✅", booking_id=b.id)
        return Response(self.get_serializer(b).data)

    @action(detail=True, methods=["post"])
    @transaction.atomic
    def reject(self, request, pk=None):
        b = self._transition(["pending"], "rejected", by_partner=True)
        b.save()
        self._refund(b)
        notify(b.user, "Booking declined", f"{b.companion} could not take {b.code}. Any wallet payment was refunded.", "⚠️", booking_id=b.id)
        return Response(self.get_serializer(b).data)

    @action(detail=True, methods=["post"], url_path="check-in")
    def check_in(self, request, pk=None):
        b = self._transition(["accepted"], "in_progress")
        b.checked_in_at = timezone.now()
        b.save()
        notify(b.user, "Service started", f"{b.companion} has checked in for {b.code}.", "🚗", "arrival", booking_id=b.id)
        return Response(self.get_serializer(b).data)

    @action(detail=True, methods=["post"], url_path="check-out")
    def check_out(self, request, pk=None):
        b = self._transition(["in_progress"], "completed")
        b.checked_out_at = timezone.now()
        b.save()
        notify(b.user, "Rate your companion", f"How was your session with {b.companion}?", "⭐", booking_id=b.id)
        return Response(self.get_serializer(b).data)

    @action(detail=True, methods=["post"])
    def location(self, request, pk=None):
        b = self.get_object()
        if b.companion.user_id != request.user.id:
            raise PermissionDenied()
        if b.status not in ("accepted", "in_progress"):
            raise ValidationError("Location sharing is only active for accepted or ongoing jobs.")
        try:
            b.lat, b.lng = float(request.data["lat"]), float(request.data["lng"])
        except (KeyError, TypeError, ValueError):
            raise ValidationError({"lat": "lat and lng are required numbers"})
        if not (-90 <= b.lat <= 90 and -180 <= b.lng <= 180):
            raise ValidationError({"lat": "Out of range"})
        b.location_at = timezone.now()
        fields = ["lat", "lng", "location_at"]
        if (b.status == "accepted" and not b.arrival_notified and b.dest_lat is not None
                and haversine_km(b.lat, b.lng, b.dest_lat, b.dest_lng) <= ARRIVAL_RADIUS_KM):
            b.arrival_notified = True
            fields.append("arrival_notified")
            notify(b.user, "Your companion has arrived", f"{b.companion} is at your location for {b.code}.", "📍",
                   "arrival", booking_id=b.id)
        b.save(update_fields=fields)
        return Response(self.get_serializer(b).data)

    @action(detail=True, methods=["post"])
    @transaction.atomic
    def rate(self, request, pk=None):
        b = self.get_object()
        if b.user_id != request.user.id or b.status != "completed":
            raise ValidationError("You can only rate your own completed bookings.")
        if hasattr(b, "review"):
            raise ValidationError("Already rated.")
        stars = int(request.data.get("stars", 0))
        if not 1 <= stars <= 5:
            raise ValidationError({"stars": "1-5"})
        Review.objects.create(booking=b, stars=stars, text=request.data.get("text", "")[:2000])
        c = b.companion
        agg = Review.objects.filter(booking__companion=c).aggregate(a=Avg("stars"), n=Count("id"))
        c.rating, c.reviews_count = round(agg["a"], 1), agg["n"]
        c.save(update_fields=["rating", "reviews_count"])
        return Response({"ok": True})


def inr(n):
    return f"₹{int(n)}"


# ---------- devices (push tokens) ----------
class DeviceView(APIView):
    def post(self, request):
        token, platform = (request.data.get("token") or "").strip(), request.data.get("platform", "")
        if not token or len(token) > 512 or platform not in ("android", "ios", "web"):
            raise ValidationError("token and platform (android|ios|web) are required")
        Device.objects.update_or_create(token=token, defaults={"user": request.user, "platform": platform})
        return Response({"ok": True}, status=201)

    def delete(self, request):
        Device.objects.filter(user=request.user, token=request.data.get("token", "")).delete()
        return Response(status=204)


# ---------- wallet / notifications / coupons ----------
class WalletView(APIView):
    def get(self, request):
        tx = WalletTx.objects.filter(user=request.user)[:50]
        return Response({"balance": request.user.wallet, "tx": s.WalletTxSerializer(tx, many=True).data})

    @transaction.atomic
    def post(self, request):
        """Top-up. In production, credit only after a verified payment-gateway webhook."""
        amt = int(request.data.get("amount", 0))
        if not 1 <= amt <= 50000:
            raise ValidationError({"amount": "Amount must be 1-50000"})
        u = User.objects.select_for_update().get(pk=request.user.pk)
        u.wallet += Decimal(amt)
        u.save(update_fields=["wallet"])
        WalletTx.objects.create(user=u, label="Added money", amount=amt)
        notify(u, "Money added", f"{inr(amt)} was added to your wallet.", "💳", "payment")
        return Response({"balance": u.wallet})


class NotificationViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    serializer_class = s.NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user)[:100]

    @action(detail=False, methods=["post"], url_path="mark-all-read")
    def mark_all_read(self, request):
        Notification.objects.filter(user=request.user, unread=True).update(unread=False)
        return Response({"ok": True})


class CouponListView(generics.ListAPIView):
    serializer_class = s.CouponSerializer
    queryset = Coupon.objects.filter(enabled=True)


@api_view(["GET"])
@permission_classes([permissions.AllowAny])
def cms_public(request):
    return Response(s.CmsItemSerializer(CmsItem.objects.all(), many=True).data)


# ---------- chat (only between parties that share a booking) ----------
class ChatView(APIView):
    def _peer(self, request, user_id):
        peer = get_object_or_404(User, pk=user_id)
        me = request.user
        linked = Booking.objects.filter(Q(user=me, companion__user=peer) | Q(user=peer, companion__user=me)).exists()
        if not (linked or me.is_admin_role):
            raise PermissionDenied("You can only chat with companions you have booked.")
        return peer

    def get(self, request, user_id):
        peer = self._peer(request, user_id)
        qs = ChatMessage.objects.filter(Q(sender=request.user, receiver=peer) | Q(sender=peer, receiver=request.user))
        qs.filter(receiver=request.user, read=False).update(read=True)
        return Response(s.ChatMessageSerializer(qs, many=True, context={"request": request}).data)

    def post(self, request, user_id):
        peer = self._peer(request, user_id)
        text = (request.data.get("text") or "").strip()
        if not text:
            raise ValidationError({"text": "Empty message"})
        m = ChatMessage.objects.create(sender=request.user, receiver=peer, text=text[:2000])
        return Response(s.ChatMessageSerializer(m, context={"request": request}).data, status=201)


# ---------- SOS / chatbot ----------
class SOSView(generics.CreateAPIView):
    serializer_class = s.SOSAlertSerializer

    def perform_create(self, ser):
        a = ser.save(user=self.request.user)
        for admin in User.objects.filter(Q(role="admin") | Q(is_superuser=True)):
            notify(admin, "SOS alert", f"{self.request.user.first_name} triggered SOS (#{a.id}).", "🆘", "emergency",
                   sos_id=a.id)


BOT = {
    "booking": "Pick a service, choose a companion, then follow the 4 steps — date, address, instructions, payment.",
    "pricing": "Pricing varies by companion, typically ₹250–₹600/hr. Filter by max price in Search.",
    "cancellation": "Cancel pending or accepted bookings from My Bookings. Wallet payments are refunded instantly.",
    "faq": "Companions are ID verified and background checked. See certifications on each profile.",
    "emergency": "Tap the red SOS button — it alerts our admin team with your location immediately.",
}


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
def chatbot(request):
    q = (request.data.get("q") or "").lower()
    key = next((k for k in BOT if k in q), None)
    return Response({"answer": BOT.get(key, "I can help with booking, pricing, cancellation, FAQ or emergency."),
                     "options": list(BOT)})


# ---------- partner ----------
class PartnerDashboard(APIView):
    permission_classes = [IsPartner]

    def get(self, request):
        c = request.user.companion
        today = timezone.localdate()
        done = Booking.objects.filter(companion=c, status="completed")

        def earn(since):
            return done.filter(checked_out_at__date__gte=since).aggregate(t=Sum("price"))["t"] or 0
        return Response({
            "companion": s.CompanionSerializer(c).data,
            "rating": c.rating, "completed": done.count(),
            "pending": Booking.objects.filter(companion=c, status="pending").count(),
            "today_jobs": Booking.objects.filter(companion=c, date=today).exclude(status__in=["cancelled", "rejected"]).count(),
            "earnings": {"daily": earn(today), "weekly": earn(today - timezone.timedelta(days=7)),
                         "monthly": earn(today - timezone.timedelta(days=30))},
        })

    def patch(self, request):
        c = request.user.companion
        if "available" in request.data:
            c.available = bool(request.data["available"])
            c.save(update_fields=["available"])
        return Response(s.CompanionSerializer(c).data)


class PartnerDocViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    permission_classes = [IsPartner]
    serializer_class = s.PartnerDocSerializer

    def get_queryset(self):
        return PartnerDoc.objects.filter(companion=self.request.user.companion)

    @action(detail=True, methods=["post"])
    def upload(self, request, pk=None):
        d = self.get_object()
        f = request.FILES.get("file")
        if not f:
            raise ValidationError({"file": "Required"})
        if f.size > 5 * 1024 * 1024 or f.content_type not in ("application/pdf", "image/jpeg", "image/png"):
            raise ValidationError({"file": "PDF/JPG/PNG up to 5MB"})
        d.file, d.verified = f, False
        d.save()
        return Response(self.get_serializer(d).data)


# ---------- admin ----------
@api_view(["GET"])
@permission_classes([IsAdminRole])
def admin_stats(request):
    users = User.objects.filter(role="user")
    rev = Booking.objects.filter(status="completed").aggregate(t=Sum("price"))["t"] or 0
    by_service = (Booking.objects.values("companion__service__name").annotate(n=Count("id")).order_by("-n")[:5])
    return Response({
        "total_users": users.count(), "active_users": users.filter(is_active=True).count(),
        "total_companions": Companion.objects.count(),
        "pending_companions": Companion.objects.filter(status="pending").count(),
        "live_services": Booking.objects.filter(status="in_progress").count(),
        "today_bookings": Booking.objects.filter(created__date=timezone.localdate()).count(),
        "revenue": rev, "open_sos": SOSAlert.objects.filter(resolved=False).count(),
        "top_services": [{"name": r["companion__service__name"], "count": r["n"]} for r in by_service],
    })


class AdminUserViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAdminRole]
    serializer_class = s.UserSerializer

    def get_queryset(self):
        qs = User.objects.all().order_by("id")
        q = self.request.query_params.get("q")
        return qs.filter(Q(first_name__icontains=q) | Q(email__icontains=q) | Q(phone__icontains=q)) if q else qs

    def perform_create(self, ser):
        u = ser.save(username=self.request.data.get("phone") or self.request.data.get("email"))
        u.set_unusable_password()
        u.save()

    @action(detail=True, methods=["post"])
    def suspend(self, request, pk=None):
        u = self.get_object()
        u.is_active = not u.is_active
        u.save(update_fields=["is_active"])
        return Response(self.get_serializer(u).data)


class AdminCompanionViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAdminRole]
    serializer_class = s.CompanionSerializer
    queryset = Companion.objects.select_related("user", "service").order_by("status", "id")

    def _set(self, status_):
        c = self.get_object()
        c.status = status_
        c.save(update_fields=["status"])
        notify(c.user, f"Profile {status_}", f"Your Maitrion profile was {status_} by the admin team.", "🛡️")
        return Response(self.get_serializer(c).data)

    @action(detail=True, methods=["post"])
    def approve(self, request, pk=None):
        return self._set("active")

    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        return self._set("rejected")

    @action(detail=True)
    def docs(self, request, pk=None):
        return Response(s.PartnerDocSerializer(self.get_object().docs.all(), many=True).data)


class AdminCouponViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAdminRole]
    serializer_class = s.CouponSerializer
    queryset = Coupon.objects.all().order_by("id")


class AdminCmsViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAdminRole]
    serializer_class = s.CmsItemSerializer
    queryset = CmsItem.objects.all().order_by("id")


class AdminFlagViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAdminRole]
    serializer_class = s.FeatureFlagSerializer
    queryset = FeatureFlag.objects.all().order_by("id")


class AdminSOSViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    permission_classes = [IsAdminRole]
    serializer_class = s.SOSAlertSerializer
    queryset = SOSAlert.objects.select_related("user").order_by("resolved", "-created")

    @action(detail=True, methods=["post"])
    def resolve(self, request, pk=None):
        a = self.get_object()
        a.resolved = True
        a.save(update_fields=["resolved"])
        return Response(self.get_serializer(a).data)


@api_view(["POST"])
@permission_classes([IsAdminRole])
def admin_broadcast(request):
    title, body = request.data.get("title", "Announcement"), request.data.get("body", "")
    if not body:
        raise ValidationError({"body": "Required"})
    users = list(User.objects.filter(is_active=True, role=request.data.get("role", "user"))
                 .exclude(notif_prefs__offers=False))
    Notification.objects.bulk_create([Notification(user=u, title=title, body=body, icon="📣", category="offers")
                                      for u in users])
    send_push(users, title, body, {"category": "offers"})
    return Response({"sent": len(users)})
