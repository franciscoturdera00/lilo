# {{PROJECT_NAME}} Codemap

**Last Updated:** (unset, fill on first task)
**Entry Points:** (main files a newcomer opens first)

This is the single orientation read for every specialist dispatch. Briefs cite it; specialists read it once and go straight to the `path:line` pointers in the brief. Keep it under about 60 lines. If it grows past that, split per area and link the parts from here.

Owner: `doc-updater` refreshes this at the end of any task that adds, moves or removes a top-level area. The PM checks the date before dispatching; if it is older than the last structural change, refresh it first.

## Layout

| Area | Where | Entry point | Tests |
|------|-------|-------------|-------|
| (example: api) | `src/api/` | `src/api/server.ts` | `tests/api/` |

## Commands

- Install:
- Run:
- Test:
- Lint / typecheck:

## Conventions worth knowing before editing

- (example: all DB access goes through `src/db/repo.ts`, never raw queries in handlers)

## Gotchas

- (things that cost a previous agent time)
