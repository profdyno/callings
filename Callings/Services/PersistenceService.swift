import Foundation

/// Loads and saves the WardData document as JSON in Application Support.
/// Writes are atomic and debounced so rapid UI mutations coalesce.
final class PersistenceService {
    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?

    init(filename: String = "WardData.json") {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent(filename)
    }

    func load() -> WardData? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WardData.self, from: data)
    }

    func scheduleSave(_ data: WardData) {
        pendingSave?.cancel()
        pendingSave = Task { [fileURL] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            Self.write(data, to: fileURL)
        }
    }

    func saveNow(_ data: WardData) {
        pendingSave?.cancel()
        Self.write(data, to: fileURL)
    }

    private static func write(_ data: WardData, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: url, options: .atomic)
    }
}
