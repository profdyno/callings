import XCTest
@testable import Callings

/// Covers the duplicate-callings bug: imported records used to get a random
/// UUID (and therefore a random CloudKit record name) on every import, so
/// syncing two imports unioned them instead of replacing.
final class WardDataRepairTests: XCTestCase {

    private func makeRow(
        _ calling: String,
        org: OrganizationKind = .otherCallings,
        subgroup: String? = "Additional Callings",
        holder: String? = nil
    ) -> ParsedCallingRow {
        ParsedCallingRow(
            organization: org,
            subgroup: subgroup,
            callingName: calling,
            isCustom: false,
            holderName: holder,
            sustainedDate: nil,
            isSetApart: false
        )
    }

    private var committeeRows: [ParsedCallingRow] {
        [
            makeRow("Activities Committee Member", holder: "Hartman, James"),
            makeRow("Activities Committee Member", holder: "Waring, Lorraine"),
            makeRow("Activities Committee Member"),
            makeRow("Ward Activities Chair", holder: "Valiulis, Gannon"),
        ]
    }

    // MARK: - Stable identity

    func testTwoDevicesImportingTheSameExportProduceIdenticalIDs() {
        var parsed = ParsedWardCallings()
        parsed.rows = committeeRows

        // Two devices, each with its own roster of the same people.
        let roster = [
            ParsedMember(name: "Hartman, James", age: 45, gender: .male),
            ParsedMember(name: "Waring, Lorraine", age: 45, gender: .female),
            ParsedMember(name: "Valiulis, Gannon", age: 45, gender: .male),
        ]
        let (deviceA, _) = ImportReconciler.applyCallings(parsed, to: ImportReconciler.applyRoster(roster, to: WardData()).0)
        let (deviceB, _) = ImportReconciler.applyCallings(parsed, to: ImportReconciler.applyRoster(roster, to: WardData()).0)

        XCTAssertEqual(
            deviceA.callingSlots.map(\.id).sorted { $0.uuidString < $1.uuidString },
            deviceB.callingSlots.map(\.id).sorted { $0.uuidString < $1.uuidString },
            "Slot identity must be content-derived, or sync unions the two imports"
        )
        XCTAssertEqual(
            Set(deviceA.callingDefinitions.map(\.id)),
            Set(deviceB.callingDefinitions.map(\.id))
        )
    }

    func testReimportKeepsSlotIdentityStable() {
        var parsed = ParsedWardCallings()
        parsed.rows = committeeRows
        let (first, _) = ImportReconciler.applyCallings(parsed, to: WardData())
        let (second, _) = ImportReconciler.applyCallings(parsed, to: first)
        XCTAssertEqual(Set(first.callingSlots.map(\.id)), Set(second.callingSlots.map(\.id)))
    }

    func testSeatsOfTheSameCallingGetDistinctIDs() {
        var parsed = ParsedWardCallings()
        parsed.rows = committeeRows
        let (data, _) = ImportReconciler.applyCallings(parsed, to: WardData())
        XCTAssertEqual(Set(data.callingSlots.map(\.id)).count, data.callingSlots.count)
    }

    // MARK: - Repair of already-duplicated data

    /// Builds the state the bug produced: two generations of the same export
    /// living side by side, each with its own random ids.
    private func duplicatedData() -> WardData {
        var parsed = ParsedWardCallings()
        parsed.rows = committeeRows
        var (data, _) = ImportReconciler.applyCallings(parsed, to: WardData())

        var older = data.callingSlots.map { slot -> CallingSlot in
            var copy = slot
            copy.id = UUID()                       // pre-fix random identity
            copy.definitionID = slot.definitionID
            copy.importOrder = slot.importOrder + 100
            return copy
        }
        // The old generation also had its own definition records.
        var strayDefinitions: [CallingDefinition] = []
        for index in older.indices {
            let original = data.callingDefinitions.first { $0.id == older[index].definitionID }!
            if let existing = strayDefinitions.first(where: { $0.importKey == original.importKey }) {
                older[index].definitionID = existing.id
            } else {
                var stray = original
                stray.id = UUID()
                strayDefinitions.append(stray)
                older[index].definitionID = stray.id
            }
        }
        data.callingDefinitions.append(contentsOf: strayDefinitions)
        data.callingSlots.append(contentsOf: older)
        return data
    }

    func testRepairCollapsesTwoGenerationsOfTheSameExport() {
        let data = duplicatedData()
        XCTAssertEqual(data.callingSlots.count, 8, "precondition: duplicated")

        let (repaired, report) = WardDataRepair.normalize(data)
        XCTAssertEqual(repaired.callingSlots.count, 4)
        XCTAssertEqual(repaired.callingDefinitions.count, 2)
        XCTAssertEqual(report.duplicateSlotsRemoved, 4)
        XCTAssertGreaterThan(report.definitionsMerged, 0)

        // Same holder never appears twice in the same calling.
        let holders = repaired.callingSlots.map { "\($0.definitionID)|\($0.holderNameRaw ?? "vacant")" }
        XCTAssertEqual(Set(holders).count, holders.count)
    }

    func testRepairIsIdempotentAndDeviceIndependent() {
        let (once, _) = WardDataRepair.normalize(duplicatedData())
        let (twice, secondReport) = WardDataRepair.normalize(once)
        XCTAssertEqual(once.callingSlots.map(\.id), twice.callingSlots.map(\.id))
        XCTAssertTrue(secondReport.isEmpty, "a repaired document must be left alone")

        // A second device with its own random ids repairs to the same result.
        let (other, _) = WardDataRepair.normalize(duplicatedData())
        XCTAssertEqual(
            Set(once.callingSlots.map(\.id)),
            Set(other.callingSlots.map(\.id)),
            "devices must converge, not keep pushing rival copies"
        )
    }

    func testRepairKeepsWorkInProgressAndRepointsIt() {
        var data = duplicatedData()
        // Work in progress attached to the *older* copy of a filled seat.
        let stale = data.callingSlots.last { $0.holderNameRaw == "Hartman, James" }!
        var entry = OpenCalling(slotID: stale.id)
        entry.releaseStatus = .approved
        entry.notes = "keep me"
        data.openCallings.append(entry)

        let (repaired, report) = WardDataRepair.normalize(data)
        let moved = repaired.openCallings.first { $0.notes == "keep me" }
        XCTAssertNotNil(moved)
        XCTAssertEqual(report.openCallingsRepointed, 1)
        let target = repaired.callingSlots.first { $0.id == moved?.slotID }
        XCTAssertEqual(target?.holderNameRaw, "Hartman, James", "entry must follow its calling")
    }

    func testRepairLeavesCleanDataAlone() {
        var parsed = ParsedWardCallings()
        parsed.rows = committeeRows
        let (clean, _) = ImportReconciler.applyCallings(parsed, to: WardData())
        let (repaired, report) = WardDataRepair.normalize(clean)
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(repaired.callingSlots.count, clean.callingSlots.count)
        XCTAssertEqual(repaired.callingDefinitions.count, clean.callingDefinitions.count)
    }

    func testRepairKeepsGenuineDuplicateVacantSeats() {
        var parsed = ParsedWardCallings()
        parsed.rows = [
            makeRow("Activities Committee Member"),
            makeRow("Activities Committee Member"),
            makeRow("Activities Committee Member", holder: "Hartman, James"),
        ]
        let (clean, _) = ImportReconciler.applyCallings(parsed, to: WardData())
        let (repaired, report) = WardDataRepair.normalize(clean)
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(repaired.callingSlots.filter { $0.holderNameRaw == nil }.count, 2,
                       "two real vacancies are not duplicates of each other")
    }

    /// A calling with nothing but empty seats has no filled holder to prove
    /// it was duplicated, so the factor comes from the rest of the document.
    func testRepairThinsVacantOnlyCallingsUsingTheDocumentWideFactor() {
        var parsed = ParsedWardCallings()
        parsed.rows = committeeRows + [
            makeRow("Ward Music Chair"),
            makeRow("Ward Music Chair"),
        ]
        var (data, _) = ImportReconciler.applyCallings(parsed, to: WardData())

        var older = data.callingSlots
        var olderDefinitions = data.callingDefinitions
        for index in olderDefinitions.indices {
            let previous = olderDefinitions[index].id
            olderDefinitions[index].id = UUID()
            for slot in older.indices where older[slot].definitionID == previous {
                older[slot].definitionID = olderDefinitions[index].id
            }
        }
        for index in older.indices {
            older[index].id = UUID()
            older[index].importOrder += 100
        }
        data.callingSlots += older
        data.callingDefinitions += olderDefinitions

        let (repaired, _) = WardDataRepair.normalize(data)
        XCTAssertEqual(repaired.callingSlots.count, 6, "duplicated document halves back to one export")
        let music = repaired.callingDefinitions.first { $0.name == "Ward Music Chair" }
        XCTAssertEqual(repaired.callingSlots.filter { $0.definitionID == music?.id }.count, 2,
                       "the two real vacant seats survive; their duplicates do not")
    }

    func testRepairPreservesAppCreatedCallingAwaitingLCR() {
        var parsed = ParsedWardCallings()
        parsed.rows = committeeRows
        var (data, _) = ImportReconciler.applyCallings(parsed, to: WardData())
        var pending = CallingDefinition(name: "Ward Drone Pilot", organization: .otherCallings, subgroup: "Additional Callings")
        pending.isPendingLCR = true
        data.callingDefinitions.append(pending)
        data.callingSlots.append(CallingSlot(definitionID: pending.id, importOrder: 99))

        let (repaired, _) = WardDataRepair.normalize(data)
        let survivor = repaired.callingDefinitions.first { $0.name == "Ward Drone Pilot" }
        XCTAssertNotNil(survivor)
        XCTAssertTrue(survivor?.isPending == true)
        XCTAssertEqual(repaired.callingSlots.filter { $0.definitionID == survivor?.id }.count, 1)
    }
}
