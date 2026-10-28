import Foundation

enum Today {
    private static let storageFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// "2026-10-28" in the user's own time zone. This is how dates are saved.
    static func dateString(_ date: Date = .now) -> String {
        storageFormat.string(from: date)
    }

    /// A saved date shown the user's way, e.g. "28 Oct 2026" or "Oct 28, 2026".
    static func display(_ saved: String) -> String {
        guard let date = storageFormat.date(from: saved) else { return saved }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
