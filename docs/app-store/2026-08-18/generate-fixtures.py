#!/usr/bin/env python3
"""Write fictional English store-capture JSON for LocalStorage."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4
from zoneinfo import ZoneInfo

OUT = Path(__file__).resolve().parent / "fixtures"
TZ = ZoneInfo("Asia/Shanghai")
NOW = datetime.now(TZ)
TODAY = NOW.replace(hour=9, minute=41, second=0, microsecond=0)
ISO = TODAY.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_local(hour: int, minute: int = 0) -> str:
    return TODAY.replace(hour=hour, minute=minute).astimezone(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def task(
    title: str,
    *,
    completed: bool,
    source: str,
    priority: int,
    hour: int | None,
) -> dict:
    due = iso_local(hour, 0) if hour is not None else None
    return {
        "id": str(uuid4()),
        "localId": str(uuid4()),
        "title": title,
        "isCompleted": completed,
        "dueDate": due,
        "source": source,
        "priority": priority,
        "syncStatus": "synced",
        "pendingDeletion": False,
        "lastModified": ISO,
    }


def event(title: str, start_h: int, end_h: int, end_m: int, source: str) -> dict:
    return {
        "id": str(uuid4()),
        "localId": str(uuid4()),
        "title": title,
        "startTime": iso_local(start_h, 0),
        "endTime": iso_local(end_h, end_m),
        "source": source,
        "participants": [],
        "isAllDay": False,
        "syncStatus": "synced",
        "lastModified": ISO,
    }


tasks = [
    task("Review project proposal", completed=True, source="Apple Calendar", priority=2, hour=9),
    task("Send weekly report", completed=False, source="Google Calendar", priority=2, hour=16),
    task("Update documentation", completed=False, source="Apple Calendar", priority=1, hour=11),
    task(
        "Evening walk",
        completed=False,
        source="Google Calendar",
        priority=0,
        hour=18,
    ),
]

events = [
    event("Team standup", 9, 9, 30, "Google Calendar"),
    event("Design review", 10, 11, 0, "Apple Calendar"),
    event("Product review", 14, 15, 0, "Google Calendar"),
]

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "tasks.json").write_text(json.dumps(tasks, indent=2) + "\n")
(OUT / "events.json").write_text(json.dumps(events, indent=2) + "\n")
print(f"wrote {len(tasks)} tasks and {len(events)} events for {TODAY.date()}")
