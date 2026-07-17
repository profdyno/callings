import Foundation

/// One row from the Ward Callings PDF: a specific seat, filled or vacant.
/// A definition may have several slots (e.g. multiple Assistant Secretaries,
/// or one filled and one vacant seat of the same calling).
struct CallingSlot: Codable, Identifiable, Hashable {
    var id = UUID()
    var definitionID: UUID
    /// nil = "Calling Vacant"
    var memberID: UUID?
    /// Holder name exactly as printed, kept as a fallback when roster matching fails.
    var holderNameRaw: String?
    var sustainedDate: Date?
    var isSetApart: Bool = false
    /// Position of the row within the PDF, preserved for stable ordering.
    var importOrder: Int = 0

    var isVacant: Bool { memberID == nil && holderNameRaw == nil }

    /// Whole months the current holder has served, from sustained date to now.
    func monthsInCalling(asOf now: Date = .now) -> Int? {
        guard let sustainedDate else { return nil }
        return Calendar.current.dateComponents([.month], from: sustainedDate, to: now).month
    }
}
