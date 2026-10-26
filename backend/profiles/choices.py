"""
Choice sets for matrimony profiles and partner preferences.

The product prototype referenced in the brief (docs/reference/paird-prototype.html)
is not present in the repository, so these sets were chosen to cover the
categories listed in the project brief. Sensitive fields (religion, community,
income) are always optional and include a "prefer not to say" path.
"""

GENDER = [("woman", "Woman"), ("man", "Man"), ("non_binary", "Non-binary")]

MARITAL_STATUS = [
    ("never_married", "Never married"),
    ("divorced", "Divorced"),
    ("separated", "Separated"),
    ("widowed", "Widowed"),
    ("annulled", "Annulled"),
]

RELIGION = [
    ("hindu", "Hindu"),
    ("muslim", "Muslim"),
    ("christian", "Christian"),
    ("sikh", "Sikh"),
    ("jain", "Jain"),
    ("buddhist", "Buddhist"),
    ("parsi", "Parsi"),
    ("jewish", "Jewish"),
    ("spiritual", "Spiritual"),
    ("no_religion", "No religion"),
    ("other", "Other"),
    ("prefer_not_to_say", "Prefer not to say"),
]

RELOCATION = [("yes", "Open to relocating"), ("maybe", "Maybe"), ("no", "Not open to relocating")]

EDUCATION_LEVEL = [
    ("high_school", "High school"),
    ("diploma", "Diploma"),
    ("bachelors", "Bachelor's degree"),
    ("masters", "Master's degree"),
    ("doctorate", "Doctorate"),
    ("professional", "Professional degree"),
    ("other", "Other"),
]

EMPLOYMENT_TYPE = [
    ("employed", "Employed"),
    ("self_employed", "Self-employed"),
    ("business", "Business owner"),
    ("government", "Government / public sector"),
    ("student", "Student"),
    ("not_working", "Not working"),
    ("other", "Other"),
]

CURRENCY = [
    ("INR", "INR"),
    ("USD", "USD"),
    ("GBP", "GBP"),
    ("EUR", "EUR"),
    ("AED", "AED"),
    ("CAD", "CAD"),
    ("AUD", "AUD"),
    ("SGD", "SGD"),
]

FAMILY_TYPE = [("nuclear", "Nuclear"), ("joint", "Joint"), ("other", "Other")]

FAMILY_VALUES = [("traditional", "Traditional"), ("moderate", "Moderate"), ("liberal", "Liberal")]

DIET = [
    ("vegetarian", "Vegetarian"),
    ("non_vegetarian", "Non-vegetarian"),
    ("eggetarian", "Eggetarian"),
    ("vegan", "Vegan"),
    ("jain", "Jain"),
    ("other", "Other"),
]

SMOKING = [("no", "Doesn't smoke"), ("occasionally", "Occasionally"), ("yes", "Smokes")]

DRINKING = [("no", "Doesn't drink"), ("socially", "Socially"), ("yes", "Drinks")]

WANTS_CHILDREN = [("yes", "Wants children"), ("no", "Doesn't want children"), ("open", "Open / not sure")]

MARRIAGE_TIMELINE = [
    ("within_6_months", "Within 6 months"),
    ("6_to_12_months", "6–12 months"),
    ("1_to_2_years", "1–2 years"),
    ("not_sure", "Not sure yet"),
]

LIVING_ARRANGEMENT = [
    ("with_family", "With family"),
    ("independent", "Independently"),
    ("flexible", "Flexible"),
]

# Privacy audiences
AUDIENCE_EVERYONE_MATCHES = [("everyone", "Everyone"), ("matches", "Matches only")]
AUDIENCE_WITH_HIDDEN = [("everyone", "Everyone"), ("matches", "Matches only"), ("hidden", "Nobody")]
INTERESTS_FROM = [("everyone", "Everyone"), ("verified", "Verified members only")]
MESSAGES_FROM = [("matches", "All matches"), ("verified_matches", "Verified matches only")]


def keys(choices):
    return [key for key, _ in choices]


ALL_CHOICES = {
    "gender": GENDER,
    "marital_status": MARITAL_STATUS,
    "religion": RELIGION,
    "open_to_relocate": RELOCATION,
    "education_level": EDUCATION_LEVEL,
    "employment_type": EMPLOYMENT_TYPE,
    "income_currency": CURRENCY,
    "family_type": FAMILY_TYPE,
    "family_values": FAMILY_VALUES,
    "diet": DIET,
    "smoking": SMOKING,
    "drinking": DRINKING,
    "wants_children": WANTS_CHILDREN,
    "marriage_timeline": MARRIAGE_TIMELINE,
    "living_arrangement": LIVING_ARRANGEMENT,
    "photo_visibility": AUDIENCE_EVERYONE_MATCHES,
    "income_visibility": AUDIENCE_WITH_HIDDEN,
    "lifestyle_visibility": AUDIENCE_WITH_HIDDEN,
    "interests_from": INTERESTS_FROM,
    "messages_from": MESSAGES_FROM,
}
