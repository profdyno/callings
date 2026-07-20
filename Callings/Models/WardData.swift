import Foundation

/// Root persisted document containing all ward data tables.
struct WardData: Codable, Equatable {
    var schemaVersion: Int = 1
    var wardName: String?
    var members: [Member] = []
    var callingDefinitions: [CallingDefinition] = []
    var callingSlots: [CallingSlot] = []
    var openCallings: [OpenCalling] = []
    var lastCallingsImport: Date?
    var lastRosterImport: Date?
    /// Bumped on every Ward Callings import so synced devices know to run
    /// the reconcile pass. Optional for decode compatibility.
    var lastImportGeneration: Int?
    /// User-managed member tags, shared across the ward (synced via
    /// WardMeta). Optional for decode compatibility.
    var customMemberTags: [String]?

    var customTags: [String] {
        get { customMemberTags ?? [] }
        set { customMemberTags = newValue }
    }

    var importGeneration: Int {
        get { lastImportGeneration ?? 0 }
        set { lastImportGeneration = newValue }
    }
}
