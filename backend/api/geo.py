from math import asin, cos, radians, sin, sqrt

AVG_SPEED_KMH = 25  # city travel speed used for ETA estimates
ARRIVAL_RADIUS_KM = 0.3


def haversine_km(lat1, lng1, lat2, lng2):
    lat1, lng1, lat2, lng2 = map(radians, (lat1, lng1, lat2, lng2))
    a = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lng2 - lng1) / 2) ** 2
    return 6371 * 2 * asin(sqrt(a))


def eta_minutes(km):
    return max(1, round(km / AVG_SPEED_KMH * 60))
