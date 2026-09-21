# Release Notes

One file per release date, named `YYYY-MM-DD.md`.

## Rules

- **One file per date.** If several changes ship on the same day, they all go
  into that date's file as a bulleted list — never create a second file for the
  same date.
- **Keep entries short but meaningful.** A reader should learn *what changed*
  and *why it matters operationally* without opening the diff. Skip pure
  formatting, typo and lint-only churn unless it changes behaviour.
- **Write for the operator, not the reviewer.** "Stage 09 now runs before the
  composite deploy" beats "refactored swim role".
- **Add the note in the same change as the code.** A behaviour change without a
  release note is an incomplete change.

## Entry format

```markdown
# 2026-09-21

- **Area — what changed.** Why it was needed and what an operator should do
  differently, if anything.
```

Use a leading bold `Area — summary.` so the file scans quickly. Common areas:
`swim`, `telemetry`, `assurance`, `templates`, `settings`, `docs`, `bootstrap`.

Notes start at **2026-09-19**; earlier history is in `git log` only.
