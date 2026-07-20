import SwiftUI

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

/// Everything about one member: profile, contact actions, current callings
/// with tenure, and the callings they're a candidate for.
struct MemberDetailSheet: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let memberID: UUID
    @State private var pickerSlot: CallingSlot?

    private var member: Member? {
        store.data.members.first { $0.id == memberID }
    }

    var body: some View {
        NavigationStack {
            if let member {
                Form {
                    profileSection(member)
                    contactSection(member)
                    churchSection(member)
                    callingsSection(member)
                    candidaciesSection(member)
                }
                .navigationTitle(member.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HelpButton(topic: .memberDetail)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .sheet(item: $pickerSlot) { slot in
                    CandidatePickerSheet(slotID: slot.id)
                }
            }
        }
    }

    private func profileSection(_ member: Member) -> some View {
        Section {
            LabeledContent("Gender", value: member.gender.map { $0 == .male ? "Male" : "Female" } ?? "—")
            LabeledContent("Age", value: member.age.map(String.init) ?? "—")
            LabeledContent("Tag") {
                CategoryMenu(member: member)
            }
        }
    }

    @ViewBuilder
    private func contactSection(_ member: Member) -> some View {
        if member.email != nil || member.phone != nil {
            Section("Contact") {
                if let email = member.email {
                    Button {
                        if let url = URL(string: "mailto:\(email)") { openURL(url) }
                    } label: {
                        Label(email, systemImage: "envelope")
                    }
                }
                if let phone = member.phone {
                    HStack {
                        Text(phone)
                        Spacer()
                        Button {
                            if let url = URL(string: "tel:\(phoneDigits(phone))") { openURL(url) }
                        } label: {
                            Image(systemName: "phone.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        Button {
                            if let url = URL(string: "sms:\(phoneDigits(phone))") { openURL(url) }
                        } label: {
                            Image(systemName: "message.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    private func churchSection(_ member: Member) -> some View {
        Section("Membership") {
            if let moveIn = member.moveInDate {
                LabeledContent("Moved in", value: moveIn.formatted(date: .abbreviated, time: .omitted))
            }
            if let recommend = member.templeRecommendStatus {
                LabeledContent("Temple recommend", value: recommend)
            }
            if member.priesthood != .none {
                LabeledContent("Priesthood", value: member.priesthood.rawValue)
            }
            if let office = member.priesthoodOffice {
                LabeledContent("Priesthood office", value: office)
            }
            if !member.classAssignments.isEmpty {
                LabeledContent("Classes", value: member.classAssignments.joined(separator: ", "))
            }
        }
    }

    @ViewBuilder
    private func callingsSection(_ member: Member) -> some View {
        let slots = store.slots(heldBy: member.id)
        if !slots.isEmpty {
            Section("Callings") {
                ForEach(slots) { slot in
                    let months = slot.monthsInCalling().map { " (\($0) mo)" } ?? ""
                    Text((store.definition(for: slot)?.name ?? "—") + months)
                }
            }
        }
    }

    @ViewBuilder
    private func candidaciesSection(_ member: Member) -> some View {
        let entries = store.activeOpenCallings.filter { $0.candidateIDs.contains(member.id) }
        if !entries.isEmpty {
            Section("Candidate For") {
                ForEach(entries) { entry in
                    if let slot = store.slotsByID[entry.slotID] {
                        Button {
                            pickerSlot = slot
                        } label: {
                            HStack {
                                Text(store.definition(for: slot)?.name ?? "—")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func phoneDigits(_ phone: String) -> String {
        phone.filter { $0.isNumber || $0 == "+" }
    }
}
