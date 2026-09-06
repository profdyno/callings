import CloudKit
import Foundation

/// The device's sync role, fixed at setup time.
enum SyncRole: String, Codable {
    case solo
    case owner
    case participant
}

struct SyncSettings: Codable, Equatable {
    var role: SyncRole = .solo
    var zoneOwnerName: String?
    var shareRecordName: String?
}

/// Sidecar persistence for everything the sync engine needs across launches:
/// the engine's own state serialization, per-record CloudKit system fields,
/// the baseline snapshot used for outbound diffing, and the sync settings.
/// Kept separate from WardData.json — different lifecycle, and wiping sync
/// state must never touch ward data.
final class SyncStateStore {

    struct State: Codable {
        var settings = SyncSettings()
        var engineStateData: Data?
        /// recordName → archived CKRecord system fields (encodeSystemFields).
        var systemFields: [String: Data] = [:]
        var baseline: WardData?
    }

    private let fileURL: URL
    private(set) var state: State

    init(filename: String = "SyncState.json") {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? Self.decoder.decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private func persist() {
        guard let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Accessors

    var settings: SyncSettings {
        get { state.settings }
        set { state.settings = newValue; persist() }
    }

    var engineStateData: Data? {
        get { state.engineStateData }
        set { state.engineStateData = newValue; persist() }
    }

    var baseline: WardData? {
        get { state.baseline }
        set { state.baseline = newValue; persist() }
    }

    // MARK: - System fields

    /// Every record name this device has seen on the server. Used to reap
    /// records the zone still holds but no local model claims.
    var knownRecordNames: Set<String> { Set(state.systemFields.keys) }

    func archiveSystemFields(of record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        state.systemFields[record.recordID.recordName] = archiver.encodedData
        persist()
    }

    /// Rebuilds a CKRecord carrying the server change tag for a known record,
    /// or nil if we've never seen it from the server.
    func archivedRecord(recordName: String) -> CKRecord? {
        guard let data = state.systemFields[recordName],
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }

    func removeSystemFields(recordName: String) {
        state.systemFields.removeValue(forKey: recordName)
        persist()
    }

    /// Wipes everything (leave/stop-sharing/account-switch).
    func reset() {
        state = State()
        persist()
    }
}
