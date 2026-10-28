import SwiftUI

extension Color {
    #if os(iOS)
    /// Competition-plate blue, same as the landing page. Lighter in dark mode so it stays readable.
    static let plate = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x6F / 255, green: 0x8C / 255, blue: 0xFF / 255, alpha: 1)
            : UIColor(red: 0x23 / 255, green: 0x47 / 255, blue: 0xC5 / 255, alpha: 1)
    })
    #else
    /// The watch is always dark, so it always uses the lighter blue.
    static let plate = Color(red: 0x6F / 255, green: 0x8C / 255, blue: 0xFF / 255)
    #endif
}
