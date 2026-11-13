"""Festival calendar for the demand features (holiday/festival flag, Section 8).

Dates for major festivals that move fresh-produce and fish demand in Maharashtra. They follow
lunar calendars, so they are listed per year; verify against the official state holiday list
before reporting results (D-68). Add years as needed.
"""

from datetime import date, timedelta
from typing import Dict, List

FESTIVALS: Dict[str, List[str]] = {
    "holi": ["2024-03-25", "2025-03-14", "2026-03-04", "2027-03-22"],
    "gudi_padwa": ["2024-04-09", "2025-03-30", "2026-03-19", "2027-04-07"],
    "eid_al_fitr": ["2024-04-11", "2025-03-31", "2026-03-20", "2027-03-10"],
    "ganesh_chaturthi": ["2024-09-07", "2025-08-27", "2026-09-14", "2027-09-04"],
    "diwali": ["2024-11-01", "2025-10-21", "2026-11-08", "2027-10-29"],
}

# Demand rises in the days before a festival and on the day itself.
LEAD_DAYS = 3

_DAYS = set()
for _dates in FESTIVALS.values():
    for _d in _dates:
        f = date.fromisoformat(_d)
        for k in range(LEAD_DAYS + 1):
            _DAYS.add(f - timedelta(days=k))


def is_festival_window(d: date) -> bool:
    return d in _DAYS
