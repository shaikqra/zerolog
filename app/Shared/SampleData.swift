import ZeroLogCore

/// Stand-in gym and history so the screens show a real engine result
/// until saved sessions and HealthKit recovery are wired in.
enum SampleData {
    static let gym: Set<String> = ["barbell", "bench", "rack", "dumbbells", "cable", "lat_pulldown", "leg_press"]

    static let history: [Session] = [
        Session(date: "2026-10-21", sessionType: "push", exercises: [
            LoggedExercise(exerciseId: "bench_press",
                           sets: Array(repeating: LoggedSet(weightKg: 60, reps: 10), count: 3)),
            LoggedExercise(exerciseId: "lateral_raise",
                           sets: Array(repeating: LoggedSet(weightKg: 8, reps: 13), count: 3)),
        ]),
        Session(date: "2026-10-23", sessionType: "pull", exercises: []),
        Session(date: "2026-10-25", sessionType: "legs", exercises: []),
    ]

    static func todaysWorkout(minutes: Int = 45) -> Workout? {
        guard let catalog = try? Catalog.bundled() else { return nil }
        return Engine.generateWorkout(catalog: catalog, gymEquipment: gym, minutes: minutes, history: history)
    }
}
