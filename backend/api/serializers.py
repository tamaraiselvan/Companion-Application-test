from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers

from .models import (Booking, ChatMessage, CmsItem, Companion, Coupon, FeatureFlag, Notification,
                     PartnerDoc, Service, SOSAlert, User, WalletTx)


class UserSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source="first_name", required=False)

    class Meta:
        model = User
        fields = ["id", "username", "name", "email", "phone", "role", "address", "language",
                  "medical", "emergency_contact", "wallet", "is_active", "date_joined"]
        read_only_fields = ["id", "username", "role", "wallet", "is_active", "date_joined"]


class RegisterSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source="first_name")
    password = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = ["name", "email", "phone", "password", "address", "emergency_contact"]

    def validate_password(self, v):
        validate_password(v)
        return v

    def create(self, data):
        pw = data.pop("password")
        user = User(username=data.get("phone") or data.get("email"), **data)
        user.set_password(pw)
        user.save()
        return user


class ServiceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Service
        fields = ["id", "slug", "name", "icon", "color", "sub"]


class CompanionSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()
    service_name = serializers.CharField(source="service.name", read_only=True)
    service_slug = serializers.CharField(source="service.slug", read_only=True)
    user_id = serializers.IntegerField(source="user.id", read_only=True)
    reviews = serializers.SerializerMethodField()

    class Meta:
        model = Companion
        fields = ["id", "user_id", "name", "service", "service_name", "service_slug", "gender", "age",
                  "languages", "price", "experience", "distance_km", "bio", "skills", "certs", "color",
                  "available", "status", "rating", "reviews_count", "reviews"]
        read_only_fields = ["status", "rating", "reviews_count"]

    def get_name(self, c):
        return c.user.get_full_name() or c.user.username

    def get_reviews(self, c):
        if not self.context.get("detail"):
            return []
        qs = Booking.objects.filter(companion=c, review__isnull=False).select_related("review", "user")[:10]
        return [{"user": b.user.first_name or b.user.username, "stars": b.review.stars,
                 "text": b.review.text} for b in qs]


class BookingSerializer(serializers.ModelSerializer):
    companion_detail = CompanionSerializer(source="companion", read_only=True)
    user_name = serializers.CharField(source="user.first_name", read_only=True)
    user_id = serializers.IntegerField(source="user.id", read_only=True)
    rated = serializers.SerializerMethodField()

    class Meta:
        model = Booking
        fields = ["id", "code", "user_id", "user_name", "companion", "companion_detail", "date", "time", "duration",
                  "address", "instructions", "payment", "coupon", "subtotal", "discount", "price",
                  "status", "checked_in_at", "checked_out_at", "lat", "lng", "rated", "created"]
        read_only_fields = ["code", "subtotal", "discount", "price", "status", "checked_in_at",
                            "checked_out_at", "lat", "lng"]

    def get_rated(self, b):
        return hasattr(b, "review")

    def validate_duration(self, v):
        if not 1 <= v <= 8:
            raise serializers.ValidationError("Duration must be 1-8 hours.")
        return v

    def validate_companion(self, c):
        if c.status != "active":
            raise serializers.ValidationError("Companion is not available for booking.")
        return c


class WalletTxSerializer(serializers.ModelSerializer):
    class Meta:
        model = WalletTx
        fields = ["id", "label", "amount", "created"]


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ["id", "icon", "title", "body", "unread", "created"]


class CouponSerializer(serializers.ModelSerializer):
    class Meta:
        model = Coupon
        fields = ["id", "code", "desc", "percent", "value", "enabled"]


class ChatMessageSerializer(serializers.ModelSerializer):
    mine = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = ["id", "text", "read", "created", "mine"]

    def get_mine(self, m):
        return m.sender_id == self.context["request"].user.id


class PartnerDocSerializer(serializers.ModelSerializer):
    uploaded = serializers.SerializerMethodField()

    class Meta:
        model = PartnerDoc
        fields = ["id", "name", "uploaded", "verified"]

    def get_uploaded(self, d):
        return bool(d.file)


class SOSAlertSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source="user.first_name", read_only=True)

    class Meta:
        model = SOSAlert
        fields = ["id", "user_name", "booking", "lat", "lng", "resolved", "created"]
        read_only_fields = ["resolved"]


class CmsItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = CmsItem
        fields = ["id", "kind", "title", "body"]


class FeatureFlagSerializer(serializers.ModelSerializer):
    class Meta:
        model = FeatureFlag
        fields = ["id", "key", "enabled"]
