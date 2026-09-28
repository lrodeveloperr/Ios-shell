import GymDayCore

/// Small display helpers shared by GymDay's own screens. Plain Japanese
/// string interpolation, not Localizable.strings keys - see the note in
/// TodayView: this is single-language product content, not shell chrome.
enum GymDayDisplay {
    static func cardioLabel(_ machine: CardioMachine) -> String {
        switch machine {
        case .treadmill: "トレッドミル"
        case .stationaryBike: "バイク"
        case .rower: "ローイングマシン"
        case .stairClimber: "ステアクライマー"
        case .elliptical: "エリプティカル"
        case .custom: "カーディオ"
        }
    }
}
