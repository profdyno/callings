import SwiftUI
import WebKit

/// In-app browser for importing straight from lcr.churchofjesuschrist.org:
/// the user signs in with their Church account (the session persists in the
/// web view's cookie store), the report loads, and Extract reads the member
/// table directly — no PDF round trip, no font corruption.
struct LCRWebImportView: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    static let memberReportURL = URL(string:
        "https://lcr.churchofjesuschrist.org/mlt/report/create-a-report/custom-reports-details/bac4fcae-2d11-4df8-bf2f-541a3ba4f16f"
    )!

    @State private var webView = WKWebView(frame: .zero, configuration: {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()  // persist the login session
        return configuration
    }())
    @State private var pendingImport: PendingImport?
    @State private var statusMessage: String?
    @State private var snapshotCopied = false
    @State private var extracting = false

    var body: some View {
        NavigationStack {
            WebViewRepresentable(webView: webView, initialURL: Self.memberReportURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Fetch from LCR")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            copySnapshot()
                        } label: {
                            Label("Copy Page Snapshot", systemImage: "doc.on.doc")
                        }
                        Button {
                            extract()
                        } label: {
                            if extracting {
                                ProgressView()
                            } else {
                                Label("Extract Members", systemImage: "square.and.arrow.down")
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                        .disabled(extracting)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(.thinMaterial)
                    }
                }
                .sheet(item: $pendingImport) { pending in
                    ImportPreviewView(pending: pending)
                }
                .alert("Snapshot Copied", isPresented: $snapshotCopied) {
                    Button("OK") {}
                } message: {
                    Text("A structural outline of the page (no member data) is on the clipboard — paste it into the chat so the importer can be adapted.")
                }
        }
    }

    private func extract() {
        extracting = true
        statusMessage = nil
        webView.evaluateJavaScript(LCRWebExtractor.scrapeScript) { result, error in
            defer { extracting = false }
            guard let json = result as? String else {
                statusMessage = "Couldn't read the page: \(error?.localizedDescription ?? "unknown error")"
                return
            }
            do {
                let table = try LCRWebExtractor.decodeScrape(json)
                let members = try LCRWebExtractor.parseMembers(from: table)
                guard members.count > 10 else {
                    statusMessage = "Only \(members.count) members found — is the full report loaded? Scroll it once, then Extract again."
                    return
                }
                let (newData, summary) = ImportReconciler.applyRoster(members, to: store.data)
                pendingImport = PendingImport(
                    kind: .memberList,
                    fileName: "LCR Member List (\(members.count) members)",
                    newData: newData,
                    summary: summary
                )
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func copySnapshot() {
        webView.evaluateJavaScript(LCRWebExtractor.snapshotScript) { result, _ in
            if let json = result as? String {
                UIPasteboard.general.string = json
                snapshotCopied = true
            }
        }
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    let initialURL: URL

    func makeUIView(context: Context) -> WKWebView {
        if webView.url == nil {
            webView.load(URLRequest(url: initialURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
