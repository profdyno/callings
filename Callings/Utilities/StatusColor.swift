import SwiftUI

extension ReleaseStatus {
    /// Proposed → red, Approved → purple, Released → blue, Announced → color removed.
    var color: Color? {
        switch self {
        case .none, .announced: return nil
        case .proposed: return .red
        case .approved: return .purple
        case .released: return .blue
        }
    }
}

extension CallStatus {
    /// Proposed → yellow, Approved → purple, Called → green, Sustained → color removed.
    var color: Color? {
        switch self {
        case .none, .sustained: return nil
        case .proposed: return .yellow
        case .approved: return .purple
        case .called: return .green
        }
    }
}
