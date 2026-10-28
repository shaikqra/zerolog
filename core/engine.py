"""ZeroLog workout engine (reference version, to be ported to Swift).

It builds today's workout from three things only: the exercise database
(data/exercises.json), the user's past sessions, and fixed progression rules.
Nothing is free-written. The same inputs always give the same workout.

History format (oldest session first):
    [{"date": "2026-10-20", "session_type": "push",
      "exercises": [{"exercise_id": "bench_press",
                     "sets": [{"weight_kg": 60, "reps": 8}, ...]}]}]

History is always stored in kg. Plans come out in the user's unit ("kg" or "lb").
"""

import json
import math
from pathlib import Path

DATA_FILE = Path(__file__).parent / "data" / "exercises.json"

WARM_UP_SECONDS = 5 * 60
WORK_SECONDS_PER_SET = 45
REST_SECONDS = {"compound": 150, "isolation": 90}
MIN_SETS = 2
DELOAD_FACTOR = 0.9
KG_PER_LB = 0.45359237


def load_catalog(path=DATA_FILE):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return {"exercises": data["exercises"], "sessions": data["sessions"]}


def next_session_type(catalog, history):
    """Rotate push -> pull -> legs, continuing from the last session."""
    order = catalog["sessions"]["order"]
    if not history:
        return order[0]
    last = history[-1]["session_type"]
    return order[(order.index(last) + 1) % len(order)]


def generate_workout(catalog, gym_equipment, minutes, history, recovery="normal", session_type=None, unit="kg"):
    if recovery not in ("normal", "low"):
        raise ValueError("recovery must be 'normal' or 'low'")
    if unit not in ("kg", "lb"):
        raise ValueError("unit must be 'kg' or 'lb'")
    session_type = session_type or next_session_type(catalog, history)

    # 1. Pick one exercise per movement slot, using only this gym's equipment.
    chosen, skipped = [], []
    for pattern in catalog["sessions"][session_type]:
        exercise = _pick_exercise(catalog, pattern, gym_equipment, history, taken=[e["id"] for e in chosen])
        if exercise:
            chosen.append(exercise)
        else:
            skipped.append({"name": pattern, "reason": "No equipment for this movement at this gym"})

    # 2. Decide weight, reps and sets for each one from past sessions.
    plan = [_prescribe(ex, history, recovery, unit) for ex in chosen]

    # 3. Shrink the workout until it fits the time available.
    _fit_to_time(plan, minutes, skipped)

    return {
        "session_type": session_type,
        "unit": unit,
        "estimated_minutes": round(_estimate_seconds(plan) / 60),
        "exercises": [{k: v for k, v in item.items() if k != "kind"} for item in plan],
        "skipped": skipped,
    }


def _pick_exercise(catalog, pattern, gym_equipment, history, taken):
    candidates = [
        ex for ex in catalog["exercises"]
        if ex["pattern"] == pattern
        and ex["id"] not in taken
        and set(ex["equipment"]) <= set(gym_equipment)
    ]
    if not candidates:
        return None
    # Prefer the exercise the user did most recently for this movement, so progression continues.
    for session in reversed(history):
        for logged in session["exercises"]:
            for ex in candidates:
                if ex["id"] == logged["exercise_id"]:
                    return ex
    return candidates[0]


def _sessions_with(history, exercise_id):
    """Past sets for one exercise, most recent session first."""
    found = []
    for session in reversed(history):
        for logged in session["exercises"]:
            if logged["exercise_id"] == exercise_id and logged["sets"]:
                found.append(logged["sets"])
    return found


def to_unit(kg, unit):
    """kg -> the user's unit, to 2 decimals so a set logged as 135 lb comes back as exactly 135."""
    return kg if unit == "kg" else round(kg / KG_PER_LB, 2)


def _in_unit(sets, unit, inc):
    """Past sets in the user's unit, snapped to the nearest weight they can load.
    This is what makes switching between kg and lb give sensible plates."""
    return [{"weight": _round(to_unit(s["weight_kg"], unit), inc), "reps": s["reps"]} for s in sets]


def _working_weight(sets):
    return max(s["weight"] for s in sets)


def _reps_at(sets, weight):
    return [s["reps"] for s in sets if s["weight"] == weight]


def _prescribe(ex, history, recovery, unit):
    low, high = ex["rep_range"]
    inc = ex["increment_kg"] if unit == "kg" else ex["increment_lb"]
    sets = ex["sets"] if recovery == "normal" else max(MIN_SETS, ex["sets"] - 1)
    item = {"exercise_id": ex["id"], "name": ex["name"], "kind": ex["kind"],
            "detectable": ex["detectable"], "sets": sets, "previous_weight": None, "change": None}

    past = [_in_unit(sets, unit, inc) for sets in _sessions_with(history, ex["id"])]
    if not past:
        item.update(weight=None, target_reps=low,
                    reason=f"First time: pick a weight you can lift for {low}-{high} reps with 2 to spare.")
        return item

    weight = _working_weight(past[0])
    reps = _reps_at(past[0], weight)
    item["previous_weight"] = weight

    if min(reps) >= high:
        if recovery == "low":
            item.update(weight=weight, target_reps=high,
                        reason=f"You earned an increase, but recovery is low today: holding at {weight:g} {unit}.")
        else:
            item.update(weight=_round(weight + inc, inc), target_reps=low, change="increased",
                        reason=f"You hit {high} reps on every set last time: +{inc:g} {unit}.")
        return item

    missed_last = min(reps) < low
    missed_before = (
        len(past) > 1
        and _working_weight(past[1]) == weight
        and min(_reps_at(past[1], weight)) < low
    )
    if missed_last and missed_before:
        new_weight = math.floor(weight * DELOAD_FACTOR / inc) * inc
        item.update(weight=_round(new_weight, inc), target_reps=low, change="deloaded",
                    reason=f"Missed {low} reps two sessions running: dropping about 10% to rebuild.")
        return item

    target = min(high, min(reps) + 1)
    item.update(weight=weight, target_reps=target,
                reason=f"Same weight as last time; aim for {target} reps per set.")
    return item


def undo_change(catalog, workout, exercise_id):
    """The user's Undo on a "What I changed" card: put one exercise back to last time's weight.
    Undoing an increase aims for the top of the rep range again; undoing a deload aims for the bottom."""
    item = next((e for e in workout["exercises"] if e["exercise_id"] == exercise_id), None)
    if item is None or item["change"] is None:
        return workout
    low, high = next(ex["rep_range"] for ex in catalog["exercises"] if ex["id"] == exercise_id)
    target = high if item["change"] == "increased" else low
    weight = item["previous_weight"]
    kept = dict(item, weight=weight, target_reps=target, change=None,
                reason=f"Kept at {weight:g} {workout['unit']}, as you asked. Aim for {target} reps.")
    return dict(workout, exercises=[kept if e is item else e for e in workout["exercises"]])


def _round(weight, inc):
    return round(round(weight / inc) * inc, 2)


def _estimate_seconds(plan):
    total = WARM_UP_SECONDS
    for item in plan:
        total += item["sets"] * (WORK_SECONDS_PER_SET + REST_SECONDS[item["kind"]])
    return total


def _fit_to_time(plan, minutes, skipped):
    """First trim sets (last exercise first, down to 2), then drop exercises from the end."""
    budget = minutes * 60
    for item in reversed(plan):
        while _estimate_seconds(plan) > budget and item["sets"] > MIN_SETS:
            item["sets"] -= 1
    while _estimate_seconds(plan) > budget and len(plan) > 1:
        dropped = plan.pop()
        skipped.append({"name": dropped["name"], "reason": "Dropped to fit your time"})


if __name__ == "__main__":
    # Demo: print a sample workout. Run with:  python engine.py
    catalog = load_catalog()
    history = [{"date": "2026-10-25", "session_type": "legs", "exercises": []},
               {"date": "2026-10-23", "session_type": "pull", "exercises": []},
               {"date": "2026-10-21", "session_type": "push", "exercises": [
                   {"exercise_id": "bench_press", "sets": [{"weight_kg": 60, "reps": 10}] * 3},
                   {"exercise_id": "lateral_raise", "sets": [{"weight_kg": 8, "reps": 13}] * 3}]}]
    history.sort(key=lambda s: s["date"])
    workout = generate_workout(catalog, {"barbell", "bench", "rack", "dumbbells", "cable"}, 45, history)
    print(json.dumps(workout, indent=2))
