from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenBlacklistView, TokenRefreshView

from . import views as v

r = DefaultRouter()
r.register("services", v.ServiceViewSet, basename="service")
r.register("companions", v.CompanionViewSet, basename="companion")
r.register("bookings", v.BookingViewSet, basename="booking")
r.register("notifications", v.NotificationViewSet, basename="notification")
r.register("partner/docs", v.PartnerDocViewSet, basename="partner-doc")
r.register("admin/users", v.AdminUserViewSet, basename="admin-user")
r.register("admin/companions", v.AdminCompanionViewSet, basename="admin-companion")
r.register("admin/coupons", v.AdminCouponViewSet, basename="admin-coupon")
r.register("admin/cms", v.AdminCmsViewSet, basename="admin-cms")
r.register("admin/flags", v.AdminFlagViewSet, basename="admin-flag")
r.register("admin/sos", v.AdminSOSViewSet, basename="admin-sos")

urlpatterns = [
    path("auth/login/", v.LoginView.as_view()),
    path("auth/otp/verify/", v.OtpVerifyView.as_view()),
    path("auth/register/", v.RegisterView.as_view()),
    path("auth/refresh/", TokenRefreshView.as_view()),
    path("auth/logout/", TokenBlacklistView.as_view()),
    path("auth/me/", v.MeView.as_view()),
    path("auth/change-password/", v.change_password),
    path("devices/", v.DeviceView.as_view()),
    path("wallet/", v.WalletView.as_view()),
    path("coupons/", v.CouponListView.as_view()),
    path("cms/", v.cms_public),
    path("chat/<int:user_id>/", v.ChatView.as_view()),
    path("sos/", v.SOSView.as_view()),
    path("bot/", v.chatbot),
    path("partner/dashboard/", v.PartnerDashboard.as_view()),
    path("admin/stats/", v.admin_stats),
    path("admin/broadcast/", v.admin_broadcast),
    path("", include(r.urls)),
]
