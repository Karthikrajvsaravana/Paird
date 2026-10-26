"""
Vibe Score — a transparent preference-fit score from 0 to 100.

The score answers one question only: "How many of the partner preferences I
set does this profile meet?" It is NOT a prediction of relationship success.

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


def vibe_score(pref, candidate, rel):
    """Return {"score": int|None, "breakdown": [...]} for a candidate profile."""
    breakdown = [{"key": key, "label": label, "met": met} for key, label, met in _criteria(pref, candidate, rel)]
    if not breakdown:
        return {"score": None, "breakdown": []}
    met = sum(1 for item in breakdown if item["met"])
    return {"score": round(100 * met / len(breakdown)), "breakdown": breakdown}
