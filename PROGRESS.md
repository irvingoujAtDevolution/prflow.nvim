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

## M4 — File picker

- Done: `:PrflowFiles` (`lua/prflow/picker.lua`) — `<status> <path> +x -y` per file; snacks picker when available, else `vim.ui.select`; selection opens the file at its first hunk.
- Tests: `tests/test_m4_picker.lua` — items match the M1 list with counts from `git diff --numstat`, counts unchanged after a file's hunks load, selecting C2 lands on line 5.
- Snacks branch: smoke-checked by hand against snacks.nvim in a headless nvim (6 items, confirm opens C2:5); not in the suite because the suite has no snacks dependency.
- Known gaps: none.

## M5 — Word diff + side-by-side float

- Done: `diff.words()` tokenizes lines (words, whitespace runs, single UTF-8 chars) and diffs tokens in-process; changed words get `PrflowAddText` in the buffer and `PrflowDeleteText` chunks in the deleted virt_lines. `:PrflowHunk` / `<leader>hd` opens base (left) and current (right) floats with `diffthis`; `q` or closing either float closes both and wipes both buffers.
- Tests: `tests/test_m5_words_float.lua` — word ranges for known edits, word extmarks on A (`{2,5,10}`, `{27,7,17}`) and the old-word chunk `3`, float contents and diff mode, no leftover windows or buffers after `q` or `:close`.
- Known gaps: old/new lines inside a changed hunk pair by position, so word highlights are rough when a hunk adds or removes lines in the middle.

## M6 — Viewed state + range switching

- Done: `<leader>hv` toggles viewed for the hunk under the cursor, saved to `<git-dir>/prflow/state.json` under `branches.<branch>.viewed.<hash>`. Viewed hunks render with `PrflowViewed` (dimmed, no word highlights); `]h` skips them unless `vim.g.prflow.show_viewed`. Hash covers path + old + new lines, so editing a viewed hunk unviews it. `:PrflowRange base|commit <sha>|since-review`, `:PrflowMarkReviewed` records HEAD under `branches.<branch>.reviewed_head`.
- Tests: `tests/test_m6_viewed_range.lua` — toggle and dim, `]h` skip and `show_viewed`, state survives stop/start (and the JSON file is keyed by branch), editing unviews, `since-review` shows only D (new commit) + E + G, `commit <sha>` shows only E + G.
- Known gaps: two identical hunks in one file share a hash, so marking one marks both. Stale hashes stay in `state.json`.

## Definition of done

- `:checkhealth prflow` (`lua/prflow/health.lua`): Neovim version, git on PATH, base ref exists. `tests/test_done.lua` checks zero `ERROR` lines in the fixture repo, and an `ERROR` for a missing ref.
- Worktrees: `tests/test_done.lua` starts review inside a `git worktree` and checks `state.json` lands in that worktree's git-dir, not the main repo's.
- README: install snippet, commands, keymaps, config table, highlights.

### Performance check

Fixture: 200 changed files under `src/` plus a 5,000-line file `big` (201 changed files).
Test: `tests/test_done.lua` → "performance: start returns fast, keystrokes wait for the debounce".
Machine: Windows 11, Neovim 0.12.4, git 2.56.

| Run | `:PrflowStart` returns | File list ready | Recompute of the 5,000-line file |
| --- | --- | --- | --- |
| 1 | 103.3 ms | 151.5 ms | 0.9 ms |
| 2 | 84.7 ms | 149.1 ms | 0.9 ms |
| 3 | 81.9 ms | 172.9 ms | 0.9 ms |
| 4 | 108.6 ms | 185.0 ms | 0.9 ms |

- `:PrflowStart` returns in 82–109 ms (budget 200 ms). Most of it is one synchronous `git rev-parse` process spawn; merge-base, name-status, numstat and ls-files run async after it returns. Base content is fetched lazily when a file opens.
- Keystroke in the large file: the test counts calls to `diff.hunks`. It is 0 right after typing and still 0 after 100 ms; it becomes 1 only after the 150 ms debounce fires.

## End-to-end check (real TUI)

- Ran Neovim 0.12.4 (Linux) in a detached WSL tmux session on the standard fixture and captured the screen (`tmux capture-pane -e`) after each step: start, status, `]h` across A → deleted B → C2, float, viewed, edit, picker, mark-reviewed, `since-review`, `base`, stop, checkhealth, `:messages`. All behaved as expected, no errors in `:messages`.
- Found and fixed: word highlights were invisible on screen. `line_hl_group` paints over any `hl_group` regardless of priority (verified with a probe in tmux). Added lines now use `hl_group` + `hl_eol` at priority 100, words at 200. Regression test: `tests/test_m5_words_float.lua` → "changed word is visibly different on screen" checks screenshot attributes.
- Full suite also passes under Linux Neovim in WSL.

## M7 — File tree sidebar + float jump (user request after M6)

- Done: `:PrflowTree` / `<leader>ht` toggles `lua/prflow/tree.lua` — a 40-column left split listing changed files by directory in stream order, with status, `+a -d`, viewed progress (`?` until a file's hunks exist), current file highlighted, fully viewed files dimmed. `<CR>` or a single mouse click (`<LeftRelease>`) opens the real file in the last used normal window at its first unviewed hunk. `]h`/`[h`, the picker and tree jumps never open files inside the tree window. `<CR>` in the hunk float jumps to that line in the real file.
- Tests: `tests/test_m7_tree.lua` — layout and order, counts and progress, `<CR>` open, mouse click via `nvim_input_mouse`, `]h` from inside the tree, current-file highlight follows navigation, toggle/stop cleanup, float `<CR>` jump.
- Real TUI: checked in WSL tmux (tree layout, open, viewed progress, dimming, current-file highlight distinct from the tree's cursorline).
- Rejected: seeding progress for all files from one `git diff -U0` (hashes differed for 13/199 files on devolutions-gateway).
- Perf note: "file list ready" grew from ~150–185 ms to ~230–400 ms after default-base detection added one serial git call; `:PrflowStart` itself still returns in 94–143 ms.
- Known gaps: directories are not collapsible; the tree lives in the tab where it was opened.

## M8 — Automatic mode (user request)

- Done: `lua/prflow/auto.lua`, `auto = true` by default. Starts on VimEnter (or immediately when loaded after it) and on DirChanged; quiet sessions stop silently when the repo or base is unusable; BufEnter/FocusGained run an async `git rev-parse HEAD --abbrev-ref HEAD` at most once a second and reload on change. `plugin/prflow.lua` defers the setup one tick so lazy.nvim `opts` are applied first.
- Tests: `tests/test_m8_auto.lua` — starts with no command, silent outside a repo then starts after `:cd`, silent without a base ref (no keymaps left), reloads on new commit and on branch switch, `:PrflowStop` stays stopped, `auto = false` stays manual.
- Real UI check: Windows `nvim.exe` with the user's full LazyVim config inside WSL tmux, opened on a fixture repo with no command typed → `prflow: feature vs origin/main (…), 6 files`, 9 extmarks in A, `]r` landed on line 3, gitsigns kept `]h`, no errors.
- Found while checking: lazy.nvim fires `VeryLazy` only after `UIEnter`, so headless runs can never show auto mode under a lazy config; real-UI checks are required for that path.

## Blocked

(none)

## Later

(none)
