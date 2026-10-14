# Progress

## M0 — Harness

- Done: repo skeleton, `Makefile` (`make test` clones pinned mini.nvim into `deps/` and runs mini.test headless), `tests/helpers/fixture.lua`.
- Tests: `tests/test_m0_harness.lua` checks the fixture builds (branch `feature`, uncommitted E, untracked G, D present).
- Known gaps: none.

## M1 — Review mode + hunk computation

- Done: `:PrflowStart [ref]`, `:PrflowStop`, `:PrflowStatus`; changed-file list (name-status -M, numstat, untracked); base content fetched once per file and cached; in-process hunks; 150 ms debounced recompute.
- Tests: `tests/test_m1_review.lua` — exact file list and statuses, A's hunk ranges, recompute after debounce with `vim.system` stubbed to fail, explicit ref, status/stop.
- Known gaps: binary files are diffed as text.

## Blocked

(none)

## Later

(none)
