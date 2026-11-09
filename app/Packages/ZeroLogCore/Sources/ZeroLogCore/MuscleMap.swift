import Foundation

/// Which mesh muscle groups a movement pattern trains, and what to call them.
///
/// This is anatomy, not UI, so it lives in Core where a Linux test can pin it:
/// every pattern in the catalog must map to at least one of the 13 groups the
/// body mesh actually ships, or the screen would ask the camera to fly to a
/// muscle that does not exist.
public enum MuscleMap {

    /// Mesh group ids trained by a movement pattern, strongest mover first.
    public static func groups(for pattern: String) -> [String] {
        switch pattern {
        case "horizontal_push":    return ["chest", "delts", "triceps"]
        case "vertical_push":      return ["delts", "triceps"]
        case "shoulder_abduction": return ["delts"]
        case "horizontal_pull":    return ["lats", "traps", "biceps"]
        case "vertical_pull":      return ["lats", "biceps"]
        case "elbow_flexion":      return ["biceps", "forearm"]
        case "elbow_extension":    return ["triceps"]
        case "hinge":              return ["hams", "glutes"]
        case "knee_dominant":      return ["quads", "glutes"]
        case "calf_raise":         return ["calves"]
        case "core_flexion":       return ["abs"]
        default:                   return []
        }
    }

    /// The one muscle the camera should frame for this pattern.
    public static func primary(for pattern: String) -> String? {
        groups(for: pattern).first
    }

    /// A human name for a mesh group id, for chips and VoiceOver.
    public static func spoken(_ group: String) -> String {
        switch group {
        case "chest":   return "Chest"
        case "delts":   return "Shoulders"
        case "biceps":  return "Biceps"
        case "triceps": return "Triceps"
        case "forearm": return "Forearms"
        case "traps":   return "Traps"
        case "lats":    return "Back"
        case "abs":     return "Abs"
        case "glutes":  return "Glutes"
        case "quads":   return "Quads"
        case "hams":    return "Hamstrings"
        case "calves":  return "Calves"
        default:        return group
        }
    }
}
