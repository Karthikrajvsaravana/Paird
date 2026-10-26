from datetime import date

from django.conf import settings
from django.utils import timezone

from profiles import choices as c
from profiles.models import Profile
from profiles.services import OTHER, get_preference, get_profile
from safety.services import blocked_user_ids
from verification.services import verified_user_ids

from .compatibility import vibe_score
from .models import Interest
from .services import active_match_user_ids


def _dob_bounds(age_min, age_max, today):
    """Convert an inclusive age range into date-of-birth bounds."""
    bounds = {}
    if age_min is not None:
        # Born on or before this date to be at least age_min.
        bounds["date_of_birth__lte"] = _years_ago(today, age_min)
    if age_max is not None:
        # Born after this date to be at most age_max.
        bounds["date_of_birth__gt"] = _years_ago(today, age_max + 1)
    return bounds


def _years_ago(today, years):
    try:
        return today.replace(year=today.year - years)
    except ValueError:
        return date(today.year - years, 2, 28)


def _clean_list(raw, allowed=None):
    values = [value.strip() for value in (raw or "").split(",") if value.strip()]
    if allowed is not None:
        values = [value for value in values if value in allowed]
    return values[:20]


def parse_filters(params):
    """Validated explicit discovery filters from query parameters."""
    filters = {}

    def int_param(name, low, high):
        value = params.get(name)
        if value in (None, ""):
            return None
        try:
            value = int(value)
        except (TypeError, ValueError):
            return None
        return max(low, min(high, value))

    min_age = settings.PAIRD["MIN_AGE"]
    filters["age_min"] = int_param("age_min", min_age, 100)
    filters["age_max"] = int_param("age_max", min_age, 100)
    filters["religions"] = _clean_list(params.get("religion"), c.keys(c.RELIGION))
    filters["countries"] = _clean_list(params.get("country"))
    filters["city"] = (params.get("city") or "").strip()[:80]
    filters["education_levels"] = _clean_list(params.get("education_level"), c.keys(c.EDUCATION_LEVEL))
    filters["marital_statuses"] = _clean_list(params.get("marital_status"), c.keys(c.MARITAL_STATUS))
    filters["marriage_timelines"] = _clean_list(params.get("marriage_timeline"), c.keys(c.MARRIAGE_TIMELINE))
    filters["verified_only"] = params.get("verified_only") in ("1", "true", "True")
    filters["with_photo"] = params.get("with_photo") in ("1", "true", "True")
    filters["use_preferences"] = params.get("use_preferences", "true") not in ("0", "false", "False")
    return filters


def _reciprocal_ok(candidate, candidate_pref, my_profile):
    """Respect the candidate's own hard preferences (gender, age)."""
    if candidate_pref is None:
        return True
    if candidate_pref.genders and my_profile.gender not in candidate_pref.genders:
        return False
    my_age = my_profile.age
    if candidate_pref.age_min is not None and (my_age is None or my_age < candidate_pref.age_min):
        return False
    if candidate_pref.age_max is not None and (my_age is None or my_age > candidate_pref.age_max):
        return False
    return True


def discover(viewer, filters):
    """
    Return the ordered list of eligible candidate Profiles for the viewer.

    Eligibility (always enforced): completed, discoverable, not paused, active
    account, not the viewer, not blocked either way, not already matched,
    no pending interest already sent by the viewer, and mutual hard
    preferences (gender, age) satisfied in both directions.
    """
    Interest.objects.expire_due()
    me = get_profile(viewer)
    my_pref = get_preference(viewer)
    today = timezone.localdate()

    excluded = {viewer.id} | blocked_user_ids(viewer) | active_match_user_ids(viewer)
    excluded |= set(
        Interest.objects.filter(sender=viewer, status=Interest.PENDING).values_list("receiver_id", flat=True)
    )

    qs = (
        Profile.objects.filter(
            completed_at__isnull=False, discoverable=True, is_paused=False, user__is_active=True
        )
        .exclude(user_id__in=excluded)
        .select_related("user", "user__identity", "user__partner_preference")
    )

    if filters.get("use_preferences", True):
        if my_pref.genders:
            qs = qs.filter(gender__in=my_pref.genders)
        age_min = filters["age_min"] if filters.get("age_min") is not None else my_pref.age_min
        age_max = filters["age_max"] if filters.get("age_max") is not None else my_pref.age_max
    else:
        age_min, age_max = filters.get("age_min"), filters.get("age_max")
    qs = qs.filter(**_dob_bounds(age_min, age_max, today))

    if filters.get("religions"):
        qs = qs.filter(religion__in=filters["religions"])
    if filters.get("countries"):
        from django.db.models import Q

        country_q = Q()
        for country in filters["countries"]:
            country_q |= Q(country__iexact=country)
        qs = qs.filter(country_q)
    if filters.get("city"):
        qs = qs.filter(city__icontains=filters["city"])
    if filters.get("education_levels"):
        qs = qs.filter(education_level__in=filters["education_levels"])
    if filters.get("marital_statuses"):
        qs = qs.filter(marital_status__in=filters["marital_statuses"])
    if filters.get("marriage_timelines"):
        qs = qs.filter(marriage_timeline__in=filters["marriage_timelines"])
    if filters.get("with_photo"):
        qs = qs.filter(user__photos__isnull=False).distinct()

    qs = qs.order_by("-last_active_at", "-completed_at", "user_id")[: settings.PAIRD["DISCOVERY_CANDIDATE_CAP"]]

    candidates = []
    for profile in qs:
        candidate_pref = getattr(profile.user, "partner_preference", None)
        if _reciprocal_ok(profile, candidate_pref, me):
            candidates.append(profile)

    if filters.get("verified_only"):
        verified = verified_user_ids([p.user_id for p in candidates])
        candidates = [p for p in candidates if p.user_id in verified]
    return candidates


def recommendations(viewer, limit=5):
    """Top candidates by Vibe Score (ties broken by recent activity)."""
    pref = get_preference(viewer)
    candidates = discover(viewer, parse_filters({}))[:100]
    scored = []
    for index, profile in enumerate(candidates):
        score = vibe_score(pref, profile, OTHER)["score"]
        scored.append((-(score if score is not None else -1), index, profile))
    scored.sort(key=lambda item: (item[0], item[1]))
    return [profile for _, _, profile in scored[:limit]]
