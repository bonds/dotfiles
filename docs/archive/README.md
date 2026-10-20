# Archive

Design documents and implementation plans for work that has **shipped**. Kept
for the rationale — why the pipeline is shaped this way, what was rejected — not
as instructions. Nothing here is maintained, and nothing should be worked in.

For things that are still true, see:

- `docs/learnings/` — platform traps, as symptom / cause / fix
- `DECISIONS.md` — settled choices and their rejected alternatives
- `AGENTS.md` — how to work in this repo

## Contents

| file | what it planned | outcome |
|---|---|---|
| `plans/2026-07-05-nix-config-refactor.md` | restructuring the flake into `flake/`, `lib/`, `modules/` | shipped |
| `specs/2026-07-05-nix-config-refactor-design.md` | the design behind that refactor | shipped |
| `plans/2026-07-07-reel-summarize.md` | building the reel-summarize pipeline | shipped (`pkgs/reel-summarize`) |
| `specs/2026-07-07-reel-summarize-design.md` | stage decomposition and error model | shipped |
| `drafts/photos-direct-rsync.md` | direct-rsync variant of the photos backup | superseded by `bin/photos-backup` + `pkgs/photokit-export` |
| `plans/photos-direct-rsync.md` | implementation plan for the above | superseded |

Supersede rather than delete: a plan that was abandoned or replaced is still a
record of why the current shape won.
