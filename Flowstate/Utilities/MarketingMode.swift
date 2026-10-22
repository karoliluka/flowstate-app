import Foundation

/// Launch with `-marketing` (debug builds only) to take store screenshots in the simulator:
/// the app looks set up as on a real phone, without permission prompts or developer tools.
enum MarketingMode {
    #if DEBUG
    static let isOn = ProcessInfo.processInfo.arguments.contains("-marketing")
    #else
    static let isOn = false
    #endif
}
