# Progress

## M0 — Harness

- Done: repo skeleton, `Makefile` (`make test` clones pinned mini.nvim into `deps/` and runs mini.test headless), `tests/helpers/fixture.lua`.
- Tests: `tests/test_m0_harness.lua` checks the fixture builds (branch `feature`, uncommitted E, untracked G, D present).
- Known gaps: none.

## M1 — Review mode + hunk computation

- Done: `:PrflowStart [ref]`, `:PrflowStop`, `:PrflowStatus`; changed-file list (name-status -M, numstat, untracked); base content fetched once per file and cached; in-process hunks; 150 ms debounced recompute.
- Tests: `tests/test_m1_review.lua` — exact file list and statuses, A's hunk ranges, recompute after debounce with `vim.system` stubbed to fail, explicit ref, status/stop.
- Known gaps: binary files are diffed as text.

## M2 — Inline rendering

- Done: `lua/prflow/render.lua` — added/changed lines get `PrflowAdd` line highlight, deleted lines render as padded `virt_lines` above the hunk (below the last line for end-of-file deletions), signs `+ ~ -`. Applies to buffers opened after start (`BufReadPost`). `:PrflowStop` clears the namespace in every buffer.
- Tests: `tests/test_m2_render.lua` — extmark rows and virt_lines on A, F opened after start, stop clears all buffers, screenshot shows `line 10`/`line 11` between `line 9` and `line 12`.
- Known gaps: deleted lines above line 1 need `topfill` to be visible (Neovim limitation); M3 navigation sets it.

## M3 — Cross-file hunk stream

- Done: `lua/prflow/stream.lua` — `order(files)` (by path), `step(dir)` walks one global list, opens the next file at its first hunk, wraps with a notification. Deleted files open as readonly `prflow://deleted/<path>` scratch buffers, wiped on stop. `]h`/`[h` set on start, configurable via `keys`, previous mappings restored on stop.
- Tests: `tests/test_m3_stream.lua` — 9 presses of `]h` visit all 9 hunks in order then wrap, `[h` reverse walk, deleted-file buffer properties and highlights, custom keys and mapping restore.
- Known gaps: none.

## Blocked

(none)

## Later

(none)
