"""
Countries and their states/provinces (data/locations.json, ODbL — see
data/LOCATIONS_LICENSE.md). Used by the app's pickers and to validate
profile locations and partner-preference countries on the server.
"""

import json
from functools import lru_cache
from pathlib import Path

_DATA = Path(__file__).resolve().parent / "data" / "locations.json"


@lru_cache(maxsize=1)
def _load():
    countries = json.loads(_DATA.read_text(encoding="utf-8"))["countries"]
    by_code = {c["code"].upper(): c for c in countries}
    by_name = {c["name"].casefold(): c for c in countries}
    return countries, by_code, by_name


def countries():
    return _load()[0]


def find_country(value):
    """Country dict for a name or ISO code (case-insensitive), or None."""
    if not value:
        return None
    _, by_code, by_name = _load()
    value = " ".join(str(value).split())
    return by_name.get(value.casefold()) or by_code.get(value.upper())


def canonical_state(country, value):
    """The listed spelling of a state within `country`, or None."""
    if not value or not country:
        return None
    wanted = " ".join(str(value).split()).casefold()
    for state in country["states"]:
        if state.casefold() == wanted:
            return state
    return None
