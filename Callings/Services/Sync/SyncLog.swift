import Foundation
import Observation
import os

/// In-memory diagnostic log of sync activity, viewable from the Sharing
/// screen. Ring-buffered; also mirrored to the system log.
@Observable
@MainActor
final class SyncLog {
    static let shared = SyncLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    private(set) var entries: [Entry] = []
    private let logger = Logger(subsystem: "com.profdyno.callings", category: "sync")

    func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        entries.append(Entry(date: .now, message: message))
        if entries.count > 300 {
            entries.removeFirst(entries.count - 300)
        }
    }

    nonisolated func post(_ message: String) {
        Task { @MainActor in self.log(message) }
    }

    var fullText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return entries
            .map { "\(formatter.string(from: $0.date)) \($0.message)" }
            .joined(separator: "\n")
    }
}
