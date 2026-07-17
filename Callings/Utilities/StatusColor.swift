import SwiftUI

extension ReleaseStatus {
    /// Open → red, Released → blue, Announced → color removed.
    var color: Color? {
        switch self {
        case .none, .announced: return nil
        case .open: return .red
        case .released: return .blue
        }
    }
}

extension CallStatus {
    /// Selected → yellow, Accepted → green, Sustained → color removed.
    var color: Color? {
        switch self {
        case .none, .sustained: return nil
        case .selected: return .yellow
        case .accepted: return .green
        }
    }
}
