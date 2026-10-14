from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from . import models as m

admin.site.register(m.User, UserAdmin)
for model in (m.Service, m.Companion, m.Booking, m.Review, m.WalletTx, m.Notification, m.Coupon,
              m.ChatMessage, m.PartnerDoc, m.SOSAlert, m.CmsItem, m.FeatureFlag):
    admin.site.register(model)
