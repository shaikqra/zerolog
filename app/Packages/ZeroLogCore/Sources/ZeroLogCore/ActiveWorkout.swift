import Foundation

/// A workout in progress. Walks through the plan set by set and records what was actually lifted.
public struct ActiveWorkout: Codable, Equatable, Sendable {
    public let plan: Workout
    public let date: String
    public private(set) var exerciseIndex = 0
    /// 1-based set number within the current exercise.
    public private(set) var setNumber = 1
    public private(set) var logged: [LoggedExercise] = []

    /// Where to step back to, one frame per confirmed set.
    ///
    /// Needed because the product rule is that EVERY automatic change can be
    /// undone, and a set logged from wrist motion is the most automatic change
    /// there is. Reconstructing the position afterwards is error-prone -- a set
    /// can be the last of an exercise, which also advanced the index -- so the
    /// position is recorded before it changes rather than inferred after.
    private var undoFrames: [UndoFrame] = []

    struct UndoFrame: Codable, Equatable, Sendable {
        let exerciseIndex: Int
        let setNumber: Int
        /// True when this set created a new LoggedExercise, so undo removes it
        /// rather than leaving an exercise with no sets in the history.
        let startedNewExercise: Bool
    }

    public init(plan: Workout, date: String) {
        self.plan = plan
        self.date = date
    }

    public var isFinished: Bool { exerciseIndex >= plan.exercises.count }

    public var current: PlannedExercise? {
        isFinished ? nil : plan.exercises[exerciseIndex]
    }

    private var setsDoneForCurrent: [LoggedSet] {
        setNumber == 1 ? [] : logged.last?.sets ?? []
    }

    /// Pre-filled weight for the next set, in the plan's unit: what you just lifted, else the plan.
    /// nil = first time, user picks.
    public var suggestedWeight: Double? {
        setsDoneForCurrent.last.map { plan.unit.fromKg($0.weightKg) } ?? current?.weight
    }

    /// Pre-filled reps for the next set: what you just did, else the target.
    public var suggestedReps: Int { setsDoneForCurrent.last?.reps ?? current?.targetReps ?? 0 }

    public var totalSetsLogged: Int { logged.reduce(0) { $0 + $1.sets.count } }

    /// Records one set (weight in the plan's unit; history keeps kg) and moves on.
    /// Returns false and changes nothing for impossible values.
    @discardableResult
    public mutating func confirmSet(weight: Double, reps: Int) -> Bool {
        guard let current, reps > 0, weight >= 0 else { return false }
        let set = LoggedSet(weightKg: plan.unit.toKg(weight), reps: reps)
        undoFrames.append(UndoFrame(exerciseIndex: exerciseIndex, setNumber: setNumber,
                                    startedNewExercise: setNumber == 1))
        if setNumber == 1 {
            logged.append(LoggedExercise(exerciseId: current.exerciseId, sets: [set]))
        } else {
            logged[logged.count - 1].sets.append(set)
        }
        if setNumber >= current.sets {
            moveToNextExercise()
        } else {
            setNumber += 1
        }
        return true
    }

    /// Takes back the last confirmed set, including one logged automatically.
    /// Returns false when there is nothing to undo.
    @discardableResult
    public mutating func undoLastSet() -> Bool {
        guard let frame = undoFrames.popLast(), !logged.isEmpty else { return false }
        if frame.startedNewExercise {
            logged.removeLast()
        } else {
            logged[logged.count - 1].sets.removeLast()
        }
        exerciseIndex = frame.exerciseIndex
        setNumber = frame.setNumber
        return true
    }

    public var canUndo: Bool { !undoFrames.isEmpty }

    public mutating func skipExercise() {
        guard !isFinished else { return }
        moveToNextExercise()
    }

    /// Stops early. Sets already confirmed are kept.
    public mutating func endEarly() {
        exerciseIndex = plan.exercises.count
        setNumber = 1
    }

    private mutating func moveToNextExercise() {
        exerciseIndex += 1
        setNumber = 1
    }

    /// What goes into history. Exercises skipped before any set are left out.
    public var session: Session {
        Session(date: date, sessionType: plan.sessionType, exercises: logged)
    }
}
