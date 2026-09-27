# Release Notes

Two files, with different jobs.

- `CHANGELOG.md` is the consolidated history: the handful of changes that still
  matter, newest first, each covering the date range over which it landed. It is
  rewritten rather than appended to.
- `YYYY-MM-DD.md` is the working note for the current day's changes, one file
  per date. Several changes on the same day all go into that date's file as a
  bulleted list — never create a second file for the same date.

Dated files are periodically folded into `CHANGELOG.md` and deleted. A dated
file is therefore the newest, least-digested account of a change; `CHANGELOG.md`
is what survives. Full history is always in `git log`.

## Rules

- **Keep entries short but meaningful.** A reader should learn *what changed*
  and *why it matters operationally* without opening the diff. Skip pure
  formatting, typo and lint-only churn unless it changes behaviour.
- **Write for the operator, not the reviewer.** "Stage 09 now runs before the
  composite deploy" beats "refactored swim role".
- **Keep the load-bearing detail.** The exact error string, version number, API
  path or command is the part that saves someone a day. Prose around it can go;
  it cannot.
- **Add the note in the same change as the code.** A behaviour change without a
  release note is an incomplete change.

## Entry format

```markdown
# 2026-09-28

- **Area — what changed.** Why it was needed and what an operator should do
  differently, if anything.
```

Use a leading bold `Area — summary.` so the file scans quickly. Common areas:
`02_data_center`, `swim`, `telemetry`, `assurance`, `templates`, `settings`,
`docs`, `bootstrap`, `process`.

Entries consolidated into `CHANGELOG.md` carry their date range in italics after
the bold summary, since they no longer live in a dated file.

Notes start at **2026-09-19**; earlier history is in `git log` only.
