# ZeroLog core

The app's logic, built and tested on Windows before there's a Mac. Python with no extra installs. Once the iPhone app exists, this gets ported to Swift, and these tests become the checklist that the Swift version must also pass.

| File | What it is |
|---|---|
| `data/exercises.json` | The exercise database: 19 exercises, what equipment each needs, rep ranges, weight steps, and the push/pull/legs session layouts. |
| `engine.py` | The workout engine. Gym equipment + time available + your past sessions + recovery → today's workout, with a reason for every weight. |
| `test_engine.py` | 16 tests proving the rules work. |

## Try it
```
cd D:\Projects\zerolog\core
python engine.py           # prints a sample workout
python -m unittest -v      # runs the tests
```

## The rules (in plain English)
- **Exercise choice:** one exercise per movement slot, only ones your gym has equipment for. It keeps whatever you did last time so progress carries over. If a gym can't support a movement, the engine says so instead of inventing something.
- **Going up:** hit the top of the rep range on every set, and the weight goes up one step next time.
- **Staying:** otherwise keep the weight and aim for one more rep.
- **Backing off:** miss the bottom of the range two sessions in a row at the same weight, and the weight drops about 10%.
- **Low recovery:** no weight increases, one set fewer per exercise.
- **Short on time:** trim sets first (never below 2), then drop exercises from the end.
- **Same inputs → same workout.** Always.
