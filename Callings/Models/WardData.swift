import Foundation

/// Root persisted document containing all ward data tables.
struct WardData: Codable {
    var schemaVersion: Int = 1
    var wardName: String?
    var members: [Member] = []
    var callingDefinitions: [CallingDefinition] = []
    var callingSlots: [CallingSlot] = []
    var openCallings: [OpenCalling] = []
    var lastCallingsImport: Date?
    var lastRosterImport: Date?
}
