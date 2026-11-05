"""
Compatibility for PairD.

`preference_fit` (formerly the whole Vibe Score) answers one question:
"How many of the partner preferences I set does this profile meet?"

`match_score` is the Vibe Score shown in the app since the match engine:
a mutual, rules-based compatibility score built from preference fit in
BOTH directions plus shared plans, values and lifestyle (see README). It is
deterministic and explainable, and NOT a prediction of relationship success.

Algorithm (deterministic):
  1. Take each preference criterion the viewer has actually set.
  2. Skip criteria whose profile value the viewer is not allowed to see
     (e.g. income hidden from non-matches, lifestyle set to "matches only").
  3. A criterion counts as met if the candidate's value satisfies it; an
     unanswered field on the candidate's profile counts as not met.
  4. score = round(100 * met / considered). Every criterion has equal weight.
  5. If the viewer has set no scorable preferences, the score is null.

Explanations list only category labels and whether they were met, so the
score never reveals hidden profile values or the candidate's own preferences.
"""

from profiles.services import audience_allows

RELOCATION_OPEN = {"yes", "maybe"}


def _in_list(value, allowed):
    return bool(value) and value in allowed


def _criteria(pref, candidate, rel):
    """Yield (key, label, met) for each applicable criterion."""
    age = candidate.age
    if pref.age_min is not None or pref.age_max is not None:
        low = pref.age_min if pref.age_min is not None else 0
        high = pref.age_max if pref.age_max is not None else 200
        yield "age", "Age", age is not None and low <= age <= high

    if pref.height_min_cm is not None or pref.height_max_cm is not None:
        low = pref.height_min_cm or 0
        high = pref.height_max_cm or 999
        yield "height", "Height", candidate.height_cm is not None and low <= candidate.height_cm <= high

    if pref.marital_statuses:
        yield "marital_status", "Marital status", _in_list(candidate.marital_status, pref.marital_statuses)

    if pref.religions:
        yield "religion", "Religion", _in_list(candidate.religion, pref.religions)

    if pref.countries:
        allowed = {country.strip().lower() for country in pref.countries}
        yield "location", "Location", bool(candidate.country) and candidate.country.strip().lower() in allowed

    if pref.requires_relocation_openness:
        yield "relocation", "Open to relocating", candidate.open_to_relocate in RELOCATION_OPEN

    if pref.education_levels:
        yield "education", "Education", _in_list(candidate.education_level, pref.education_levels)

    if pref.employment_types:
        yield "career", "Career", _in_list(candidate.employment_type, pref.employment_types)

    if pref.income_min is not None and pref.income_currency and audience_allows(candidate.income_visibility, rel):
        met = (
            candidate.annual_income is not None
            and candidate.income_currency == pref.income_currency
            and candidate.annual_income >= pref.income_min
        )
        yield "income", "Income", met

    if pref.wants_children:
        yield "children", "Children", _in_list(candidate.wants_children, pref.wants_children)

    if pref.marriage_timelines:
        yield "timeline", "Marriage timeline", _in_list(candidate.marriage_timeline, pref.marriage_timelines)

    if pref.living_arrangements:
        yield "living", "Living arrangement", _in_list(candidate.living_arrangement, pref.living_arrangements)

    if audience_allows(candidate.lifestyle_visibility, rel):
        if pref.diets:
            yield "diet", "Diet", _in_list(candidate.diet, pref.diets)
        if pref.smoking:
            yield "smoking", "Smoking", _in_list(candidate.smoking, pref.smoking)
        if pref.drinking:
            yield "drinking", "Drinking", _in_list(candidate.drinking, pref.drinking)


def preference_fit(pref, candidate, rel):
    """Return {"score": int|None, "breakdown": [...]} for a candidate profile."""
    breakdown = [{"key": key, "label": label, "met": met} for key, label, met in _criteria(pref, candidate, rel)]
    if not breakdown:
        return {"score": None, "breakdown": []}
    met = sum(1 for item in breakdown if item["met"])
    return {"score": round(100 * met / len(breakdown)), "breakdown": breakdown}


# ---------------------------------------------------------------------------
# Match engine
# ---------------------------------------------------------------------------

TIMELINE_ORDER = ["within_6_months", "6_to_12_months", "1_to_2_years"]
VALUES_ORDER = ["traditional", "moderate", "liberal"]
DIET_PAIRS = {
    frozenset(["vegetarian", "eggetarian"]): 0.8,
    frozenset(["vegetarian", "jain"]): 0.85,
    frozenset(["vegetarian", "vegan"]): 0.8,
    frozenset(["eggetarian", "non_vegetarian"]): 0.75,
    frozenset(["vegetarian", "non_vegetarian"]): 0.5,
    frozenset(["jain", "non_vegetarian"]): 0.3,
    frozenset(["vegan", "non_vegetarian"]): 0.3,
}
HABIT_ORDER = {"smoking": ["no", "occasionally", "yes"], "drinking": ["no", "socially", "yes"]}

# Weights of each factor in the final score (only factors with data count).
WEIGHTS = {
    "your_fit": 30,  # what the viewer explicitly asked for counts most
    "their_fit": 30,  # ...and so does what the candidate asked for
    "children": 12,
    "timeline": 9,
    "lifestyle": 8,
    "location": 6,
    "family_values": 3,
    "living": 2,
}
LABELS = {
    "your_fit": "Your preferences",
    "their_fit": "What they're looking for",
    "children": "Children",
    "timeline": "Marriage timeline",
    "lifestyle": "Lifestyle",
    "location": "Location",
    "family_values": "Family values",
    "living": "Living arrangement",
}
DEALBREAKER_CAP = 35
PREFERENCE_FLOOR = 0.7  # meeting none of someone's stated preferences keeps 70% of the score


def _ordered_closeness(a, b, order):
    if a not in order or b not in order:
        return None
    gap = abs(order.index(a) - order.index(b))
    return {0: 1.0, 1: 0.7}.get(gap, 0.35)


def _children(a, b):
    if not a or not b:
        return None, False
    if a == b:
        return 1.0, False
    if "open" in (a, b):
        return 0.7, False
    return 0.0, True  # one wants children, the other doesn't


def _timeline(a, b):
    if not a or not b:
        return None
    if "not_sure" in (a, b):
        return 0.6 if a != b else 0.8
    return _ordered_closeness(a, b, TIMELINE_ORDER)


def _diet(a, b):
    if not a or not b:
        return None
    if a == b:
        return 1.0
    if "other" in (a, b):
        return 0.6
    return DIET_PAIRS.get(frozenset([a, b]), 0.5)


def _habit(kind, a, b):
    if not a or not b:
        return None
    return {0: 1.0, 1: 0.6}.get(abs(HABIT_ORDER[kind].index(a) - HABIT_ORDER[kind].index(b)), 0.2)


def _lifestyle(me, other):
    parts = [
        _diet(me.diet, other.diet),
        _habit("smoking", me.smoking, other.smoking),
        _habit("drinking", me.drinking, other.drinking),
    ]
    parts = [p for p in parts if p is not None]
    return sum(parts) / len(parts) if parts else None


def _location(me, other):
    if not me.country or not other.country:
        return None
    same = lambda a, b: bool(a) and bool(b) and a.strip().casefold() == b.strip().casefold()  # noqa: E731
    if same(me.country, other.country):
        if same(me.city, other.city):
            return 1.0
        if same(me.state, other.state):
            return 0.85
        return 0.7
    openness = {me.open_to_relocate, other.open_to_relocate}
    if "yes" in openness:
        return 0.6
    if "maybe" in openness:
        return 0.45
    return 0.25


def _living(a, b):
    if not a or not b:
        return None
    if a == b:
        return 1.0
    if "flexible" in (a, b):
        return 0.8
    return 0.4


def match_score(viewer_profile, viewer_pref, candidate, candidate_pref, rel):
    """
    Mutual compatibility of `candidate` for `viewer_profile`, 0-100.

    Uses only what the viewer may see of the candidate (lifestyle and income
    respect the candidate's privacy settings). The candidate's own partner
    preferences are applied but never revealed: the breakdown says only
    whether the viewer fits what they are looking for overall.

    Returns {"score": int|None, "breakdown": [{key, label, met}], "dealbreakers": [labels]}.
    """
    factors = {}
    dealbreakers = []

    if viewer_pref is not None:
        fit = preference_fit(viewer_pref, candidate, rel)["score"]
        if fit is not None:
            factors["your_fit"] = fit / 100
    if candidate_pref is not None:
        # How the viewer looks to the candidate: the viewer's privacy applies.
        fit = preference_fit(candidate_pref, viewer_profile, rel)["score"]
        if fit is not None:
            factors["their_fit"] = fit / 100

    children, conflict = _children(viewer_profile.wants_children, candidate.wants_children)
    if children is not None:
        factors["children"] = children
        if conflict:
            dealbreakers.append(LABELS["children"])
    timeline = _timeline(viewer_profile.marriage_timeline, candidate.marriage_timeline)
    if timeline is not None:
        factors["timeline"] = timeline
    if audience_allows(candidate.lifestyle_visibility, rel):
        lifestyle = _lifestyle(viewer_profile, candidate)
        if lifestyle is not None:
            factors["lifestyle"] = lifestyle
    location = _location(viewer_profile, candidate)
    if location is not None:
        factors["location"] = location
    values = _ordered_closeness(viewer_profile.family_values, candidate.family_values, VALUES_ORDER)
    if values is not None:
        factors["family_values"] = values
    living = _living(viewer_profile.living_arrangement, candidate.living_arrangement)
    if living is not None:
        factors["living"] = living

    if not factors:
        return {"score": None, "breakdown": [], "dealbreakers": []}
    total_weight = sum(WEIGHTS[key] for key in factors)
    score = 100 * sum(WEIGHTS[key] * value for key, value in factors.items()) / total_weight
    # Explicitly stated preferences that aren't met scale the whole score down
    # (from either side), so shared lifestyle can't outweigh what people asked for.
    for key in ("your_fit", "their_fit"):
        if key in factors:
            score *= PREFERENCE_FLOOR + (1 - PREFERENCE_FLOOR) * factors[key]
    score = round(score)
    if dealbreakers:
        score = min(score, DEALBREAKER_CAP)
    ordered = sorted(factors, key=lambda key: -WEIGHTS[key])
    breakdown = [{"key": key, "label": LABELS[key], "met": factors[key] >= 0.65} for key in ordered]
    return {"score": score, "breakdown": breakdown, "dealbreakers": dealbreakers}


def vibe_for(viewer, candidate, rel, viewer_pref=None):
    """Vibe Score payload for the API (viewer is a User, candidate a Profile)."""
    from profiles.models import PartnerPreference
    from profiles.services import get_preference, get_profile

    viewer_pref = viewer_pref or get_preference(viewer)
    try:
        candidate_pref = candidate.user.partner_preference
    except PartnerPreference.DoesNotExist:
        candidate_pref = None
    return match_score(get_profile(viewer), viewer_pref, candidate, candidate_pref, rel)
