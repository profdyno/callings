# Gotchas

Lessons learned building this app — review before touching the parsers or CI.

## PDF parsing (LCR exports)

- **`PDFPage.characterBounds(at:)` returns garbage for LCR PDFs** (dropped
  glyphs, drifting coordinates). One-character `PDFSelection` bounds
  (`page.selection(for: NSRange).bounds(for: page)`) are reliable. Also note
  the index is UTF-16 code units, not Swift `Character`s.
- **`PDFPage.string` text order interleaves wrapped table cells** — parsing
  must be geometry-based (cluster glyphs by y into lines, split cells by
  column x-bands), never by text order.
- **Column x-positions shift between sections** in the Ward Callings export
  (e.g. "Additional … Callings" tables). Re-capture band origins at every
  repeated "Calling Name Sustained Set Apart" header line.
- **The ward/stake header repeats at the top of most pages** and ends with a
  unit ID like "(508225)". If not filtered on *every* page it gets classified
  as a subgroup header. Conversely, once filtered, the last data row of a
  page sits directly before a page-continuation column header — subgroup
  detection must require a single contiguous run so data rows aren't
  swallowed (5 rows were silently lost this way).
- **Member list rows split across page breaks in both directions**: a row's
  trailing cells can continue onto the next page (merge into previous
  member), and a row's *name* can land on the next page while age/gender
  stay behind (stitch tail + head blocks). One member of 445 was lost until
  both cases were handled. The report's final "Count: N" line is the
  validation anchor — always compare.
- **Roster matching must be exact-name only.** Loose "last name + first
  token" matching merged "Bingham, Ryan" with "Bingham, Ryan Kirk Jr."
  (father/son). Loose/prefix matching is only safe for callings-PDF holder
  names ("Woodruff, Sam" vs "Woodruff, Samuel B"), and only when unambiguous.
- **Holders may legitimately not be on the roster** (out-of-unit callings).
  Keep them as placeholder members; don't treat as parse failures.
- The member list's Priesthood column is track-level only
  ("Aaronic"/"Melchizedek"), not office-level — the model reflects that.
- **LCR PDFs saved from a laptop browser can be textless** (corrupt Type0
  fonts — PDFKit extracts empty strings), while the SAME report saved from
  the iPad parses perfectly (219 rows, 0 mismatches). If a PDF import
  reports "unreadable", re-save the report on the iPad before debugging
  the parser.

## CloudKit sync

- **A synced record's identity must be derived from content, never from a
  fresh `UUID()`.** Imported callings used to get a new `UUID()` per import,
  and the CKRecord name comes from the id — so two imports of the same report
  were two disjoint record sets. `integrate` upserts by id, so it unioned
  them instead of replacing, and the ward board showed two generations of the
  same export side by side. `StableID` derives definition ids from the LCR
  import key and slot ids from definition + seat number, so every device and
  every import agree on what a record is called.
- **Every mutation path must notify the sync observer.** `WardStore.apply` —
  the import commit, the one place that replaces *every* slot — didn't, so an
  import never enqueued the deletions for the records it retired. They sat in
  the zone until some full re-fetch replayed them.
- **The baseline diff alone can't reap abandoned records.** Anything that
  resets the baseline (enabling sharing, stop-and-restart, resync) hides
  deletions that were never sent. `orphanedServerRecordNames` compares the
  archived system-fields keys (every record this device has seen on the
  server) against the live models, gated on a populated document so a wipe or
  a half-finished first fetch can't be mistaken for mass deletion.
- **The bug can lie dormant for weeks.** The orphans only became visible on a
  "Re-download All Data" / new participant join — six weeks after the code
  that caused them last changed. When a data bug "starts this week" with no
  commits that week, look for the operational event that replayed old state.
- **Repair passes must be deterministic, not just correct.** `WardDataRepair`
  runs on every launch; because its output depends only on content, every
  device converges on the same result instead of pushing rival cleanups.

## SwiftUI (iPadOS)

- **iPadOS `Table` silently drops its FIRST `Section` header** — and
  `Section("") {}` doesn't compile in a TableRowBuilder. Workaround (see
  ActionsView): flatten to a row enum and render styled header rows.
- **A `.popover` whose `isPresented` is true at first render crashes** —
  UIKit throws in `UIPopoverPresentationController presentationTransition-
  WillBegin` because the toolbar button has no anchor yet (hit via the
  `-help` launch arg initializing `@State showing = true`). Present from
  `.task` after a short delay instead.
- **`Text` inside a ScrollView inside a popover truncates with "…"
  instead of wrapping** (inconsistently — some lines wrap, some don't).
  Fix: `.fixedSize(horizontal: false, vertical: true)` on the Text.

## iPhone / compact width

- **SwiftUI `Table` renders ONLY its first column in compact width.** Not a
  narrower table — the other columns simply vanish. Open Callings would have
  shown nothing but its 28pt icon column on a phone. Every `Table` view needs
  a `List`-of-rows alternative behind
  `@Environment(\.horizontalSizeClass)`; build it from the same cell views
  (`ReleaseStatusCell`, `AssignedCell`, `CandidatesCell`, `ToBeCalledCell`,
  `StatusMenu`) so role gating and the status ladders can't drift apart.
- **A `GridRow` body can't be reused outside a `Grid`.** `CallingRowView` was
  a `GridRow`, so the phone list couldn't use it. Split the presentation into
  a model plus per-cell views; the grid composes them in a `GridRow`, the list
  in an `HStack`, and neither owns the styling.
- **`HomeGroup` helpers that read the store need `@MainActor`** — `WardStore`
  is main-actor isolated, so a plain `func slots(in store:)` on a nonisolated
  enum won't compile.
- **Don't port the iPad's five-column workflow row verbatim.** Showing
  Assigned / Candidates / To call / Assigned as "—" for every quiet calling
  put three callings on a screen; hiding them until an entry exists puts six.
- **List rows are far looser than a `Grid`.** The ward board uses
  `verticalSpacing: 3`; the equivalent list needs explicit `listRowInsets`
  and `defaultMinListRowHeight` or it reads at half the density.

## Build / CI

- Bare `/regex/` literals don't compile in Swift 5 mode; use `#/regex/#`.
- Only `main.swift` may contain top-level code when compiling multiple files
  with `swiftc` (handy for running parsers as a macOS CLI against real PDFs).
- Simulator runtime isn't bundled with Xcode: `xcodebuild -downloadPlatform iOS`.
- CI runner simulator device names change with Xcode versions — discover an
  iPad at runtime (`xcrun simctl list devices available | grep iPad`).
- GitHub repo secrets are write-only; they can't be read back or copied
  between repos except by a workflow running inside the source repo.
- Apple's App Store Connect API refuses everything ("required agreement is
  missing or has expired") until the account holder re-accepts the yearly
  Free Apps Agreement in ASC → Business → Agreements. This silently broke
  the habits weekly build too.
- App ID *names* (not bundle IDs) reject underscores — "Callings MBB", not
  "Callings_MBB".
- `upload_to_testflight` cannot create the App Store Connect app record;
  it must be created once by hand (ASC → My Apps → +). The public API has
  no create-app endpoint.
- Don't trust `gh run watch --exit-status` piped through other commands —
  check `gh run view --json conclusion` for the real outcome.

## Data safety

- `import/*.pdf` and `screenshots/` contain real member PII — gitignored,
  never commit. Test fixtures against real PDFs use `XCTSkipUnless` on the
  local file path so CI (no PDFs) skips them.
- **The roster PDF's font maps ligature glyphs to wrong letters**: "ﬀ"
  extracts as 'g' ("Jeff"→"Jeg") and "ﬂ" as 'j' ("Shiflett"→"Shijett") —
  this silently created 8 false placeholder members. Repaired by glyph
  geometry in `MemberListParser.correctingLigatures` (ligature glyphs are
  ~25%+ wider than the real letters); thresholds are calibrated to the
  report's body font and guarded by height to skip the footer font.
- **CloudKit data does not cross environments.** Xcode dev builds write to
  the Development environment; TestFlight/App Store builds use Production.
  Starting the share from a dev build uploads data + share to Development —
  the schema deploy copies only the SCHEMA to Production, never records.
  Owner must run "Start Sharing" from the same kind of build participants
  use (TestFlight). The Sharing screen now shows the environment, and the
  owner has a Stop Sharing & Reset button to redo setup.
- **CloudKit only adds a field to the schema when some record stores a
  non-nil value in it.** Optional fields that were empty on every record
  during the Development-environment exercise are missing from the deployed
  Production schema, and Production then rejects any save touching them
  (CKError 12: "Cannot create or modify field X in production schema") —
  which looked like "assignments/statuses don't sync" while candidate adds
  on fresh records worked. Fix: add the missing fields by hand in CloudKit
  Console (Development → Schema → Record Types) and redeploy. Prevention:
  exercise every optional field before a schema deploy, or maintain the
  schema deliberately in the Console.
- **`latest_testflight_build_number` is blind to builds still in Apple's
  processing queue** — while one build is "Processing", the next CI run
  reuses its number and the upload is rejected (-19232). Fixed by taking
  `max(latest+1, GITHUB_RUN_NUMBER)`.
