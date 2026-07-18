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
