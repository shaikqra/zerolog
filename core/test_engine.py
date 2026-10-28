"""Tests for the workout engine. Run from this folder with:  python -m unittest -v"""

import json
import unittest

from engine import generate_workout, load_catalog, next_session_type

CATALOG = load_catalog()
FULL_GYM = {"barbell", "bench", "rack", "dumbbells", "cable", "lat_pulldown", "leg_press"}
DUMBBELLS_ONLY = {"dumbbells", "bench"}


def session(date, session_type, exercise_id, weight, reps_per_set):
    return {"date": date, "session_type": session_type,
            "exercises": [{"exercise_id": exercise_id,
                           "sets": [{"weight_kg": weight, "reps": r} for r in reps_per_set]}]}


def find(workout, exercise_id):
    return next(e for e in workout["exercises"] if e["exercise_id"] == exercise_id)


class Database(unittest.TestCase):
    def test_every_exercise_uses_known_equipment(self):
        with open("data/exercises.json", encoding="utf-8") as f:
            known = {e["id"] for e in json.load(f)["equipment_types"]}
        for ex in CATALOG["exercises"]:
            self.assertLessEqual(set(ex["equipment"]), known, ex["id"])


class Selection(unittest.TestCase):
    def test_only_uses_equipment_the_gym_has(self):
        equipment_by_id = {e["id"]: set(e["equipment"]) for e in CATALOG["exercises"]}
        for session_type in ("push", "pull", "legs"):
            w = generate_workout(CATALOG, DUMBBELLS_ONLY, 90, [], session_type=session_type)
            for item in w["exercises"]:
                self.assertLessEqual(equipment_by_id[item["exercise_id"]], DUMBBELLS_ONLY)

    def test_missing_equipment_is_reported_not_invented(self):
        w = generate_workout(CATALOG, DUMBBELLS_ONLY, 90, [], session_type="pull")
        self.assertIn("vertical_pull", [s["name"] for s in w["skipped"]])

    def test_same_inputs_give_same_workout(self):
        history = [session("2026-10-21", "push", "bench_press", 60, [8, 8, 7])]
        a = generate_workout(CATALOG, FULL_GYM, 45, history)
        b = generate_workout(CATALOG, FULL_GYM, 45, history)
        self.assertEqual(a, b)

    def test_keeps_the_exercise_you_did_last_time(self):
        history = [session("2026-10-21", "push", "db_bench_press", 24, [10, 10, 9])]
        w = generate_workout(CATALOG, FULL_GYM, 60, history, session_type="push")
        self.assertEqual(w["exercises"][0]["exercise_id"], "db_bench_press")

    def test_legs_day_picks_two_different_knee_exercises(self):
        w = generate_workout(CATALOG, FULL_GYM, 90, [], session_type="legs")
        ids = [e["exercise_id"] for e in w["exercises"]]
        self.assertEqual(len(ids), len(set(ids)))

    def test_rotation_follows_push_pull_legs(self):
        self.assertEqual(next_session_type(CATALOG, []), "push")
        self.assertEqual(next_session_type(CATALOG, [{"session_type": "push", "exercises": []}]), "pull")
        self.assertEqual(next_session_type(CATALOG, [{"session_type": "legs", "exercises": []}]), "push")


class Progression(unittest.TestCase):
    def test_first_time_has_no_weight_and_explains_why(self):
        w = generate_workout(CATALOG, FULL_GYM, 60, [], session_type="push")
        bench = find(w, "bench_press")
        self.assertIsNone(bench["weight_kg"])
        self.assertIn("First time", bench["reason"])

    def test_top_of_range_on_every_set_adds_weight(self):
        history = [session("2026-10-21", "push", "bench_press", 60, [10, 10, 10])]
        bench = find(generate_workout(CATALOG, FULL_GYM, 60, history, session_type="push"), "bench_press")
        self.assertEqual(bench["weight_kg"], 62.5)
        self.assertEqual(bench["target_reps"], 6)

    def test_otherwise_holds_weight_and_aims_one_rep_higher(self):
        history = [session("2026-10-21", "push", "bench_press", 60, [9, 8, 7])]
        bench = find(generate_workout(CATALOG, FULL_GYM, 60, history, session_type="push"), "bench_press")
        self.assertEqual(bench["weight_kg"], 60)
        self.assertEqual(bench["target_reps"], 8)

    def test_two_misses_in_a_row_drops_about_ten_percent(self):
        history = [session("2026-10-17", "push", "bench_press", 60, [6, 5, 4]),
                   session("2026-10-21", "push", "bench_press", 60, [6, 5, 5])]
        bench = find(generate_workout(CATALOG, FULL_GYM, 60, history, session_type="push"), "bench_press")
        self.assertEqual(bench["weight_kg"], 52.5)  # 54 kg rounded down to the 2.5 kg step

    def test_one_miss_alone_does_not_deload(self):
        history = [session("2026-10-21", "push", "bench_press", 60, [6, 5, 5])]
        bench = find(generate_workout(CATALOG, FULL_GYM, 60, history, session_type="push"), "bench_press")
        self.assertEqual(bench["weight_kg"], 60)


class Recovery(unittest.TestCase):
    def test_low_recovery_holds_weight_and_cuts_a_set(self):
        history = [session("2026-10-21", "push", "bench_press", 60, [10, 10, 10])]
        bench = find(generate_workout(CATALOG, FULL_GYM, 60, history, recovery="low", session_type="push"),
                     "bench_press")
        self.assertEqual(bench["weight_kg"], 60)
        self.assertEqual(bench["sets"], 2)
        self.assertIn("recovery is low", bench["reason"])

    def test_unknown_recovery_value_is_rejected(self):
        with self.assertRaises(ValueError):
            generate_workout(CATALOG, FULL_GYM, 60, [], recovery="tired")


class Time(unittest.TestCase):
    def test_fits_inside_the_time_available(self):
        for minutes in (20, 30, 45, 60):
            w = generate_workout(CATALOG, FULL_GYM, minutes, [], session_type="push")
            self.assertLessEqual(w["estimated_minutes"], minutes)

    def test_plenty_of_time_keeps_the_full_session(self):
        w = generate_workout(CATALOG, FULL_GYM, 90, [], session_type="push")
        self.assertEqual(len(w["exercises"]), 4)
        self.assertTrue(all(e["sets"] == 3 for e in w["exercises"]))

    def test_short_session_trims_sets_before_dropping_exercises(self):
        w = generate_workout(CATALOG, FULL_GYM, 30, [], session_type="push")
        self.assertEqual(len(w["exercises"]), 4)
        self.assertTrue(any(e["sets"] == 2 for e in w["exercises"]))


if __name__ == "__main__":
    unittest.main()
