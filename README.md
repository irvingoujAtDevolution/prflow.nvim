# prflow.nvim

Review every change on your branch against its base, right in your normal buffers.

There is no diff view. Review mode is a global on/off state: the diff is drawn over the
files you already edit, LSP keeps working, and one hunk stream runs across all changed files.

- Added and changed lines are highlighted; deleted lines show inline as virtual lines.
- Changed words are highlighted inside changed lines.
- `]h` / `[h` walk every hunk of every changed file in one ordered list.
- Mark hunks as viewed; viewed state is saved per branch and survives restarts.
- Review "since my last review" with `:PrflowRange since-review`.

Requires Neovim 0.10+ and `git`. No other dependencies;
[snacks.nvim](https://github.com/folke/snacks.nvim) is used for the file picker when installed.

## Install (lazy.nvim)

```lua
{
  dir = 'D:/prflow.nvim', -- local checkout; use '<owner>/prflow.nvim' once it is on GitHub
  name = 'prflow.nvim',
  cmd = { 'PrflowStart', 'PrflowStop', 'PrflowStatus', 'PrflowFiles', 'PrflowHunk', 'PrflowRange', 'PrflowMarkReviewed' },
  opts = {},
}
```

## Commands

| Command | What it does |
| --- | --- |
| `:PrflowStart [ref]` | Start review mode against the merge-base of `ref` (default `origin/main`) and `HEAD`. |
| `:PrflowStop` | Leave review mode and clear every highlight. |
| `:PrflowStatus` | Show branch, base and number of changed files. |
| `:PrflowFiles` | Pick a changed file (`status path +added -removed`); opens it at its first hunk. |
| `:PrflowHunk` | Show the hunk under the cursor side by side (base left, current right). `q` closes it. |
| `:PrflowRange base` | Diff against the merge-base again. |
| `:PrflowRange commit <sha>` | Diff against a specific commit. |
| `:PrflowRange since-review` | Diff against the `HEAD` recorded by `:PrflowMarkReviewed`. |
| `:PrflowMarkReviewed` | Record the current `HEAD` as reviewed for this branch. |

The changed-file list includes uncommitted edits to tracked files and untracked files
(shown as added). Deleted files open as read-only `prflow://deleted/<path>` buffers.

## Default keymaps

Set when review mode starts and removed when it stops. Any mapping you had on the same
key is restored on stop.

| Key | Action |
| --- | --- |
| `]h` | Next hunk (moves to the next file after the last hunk; wraps at the end). |
| `[h` | Previous hunk. |
| `<leader>hd` | Side-by-side view of the hunk under the cursor. |
| `<leader>hv` | Toggle viewed for the hunk under the cursor. |

## Configuration

Pass options to `setup()` (or `opts` in lazy.nvim), or set `vim.g.prflow` directly.
These are the defaults:

```lua
require('prflow').setup({
  base = 'origin/main',  -- ref used by :PrflowStart without an argument
  debounce_ms = 150,     -- wait after the last edit before recomputing hunks
  show_viewed = false,   -- true: ]h / [h also stop on viewed hunks
  keys = {               -- set a key to false to skip that mapping
    next = ']h',
    prev = '[h',
    hunk = '<leader>hd',
    viewed = '<leader>hv',
  },
})
```

## Highlights

All are default links, so a colorscheme can override them.

| Group | Default link | Used for |
| --- | --- | --- |
| `PrflowAdd` | `DiffAdd` | Added and changed lines |
| `PrflowDelete` | `DiffDelete` | Deleted lines (virtual lines) |
| `PrflowAddText` / `PrflowDeleteText` | `DiffText` | Changed words |
| `PrflowAddSign` / `PrflowChangeSign` / `PrflowDeleteSign` | `Added` / `Changed` / `Removed` | Sign column |
| `PrflowViewed` | `Comment` | Hunks marked as viewed |

## Lua API

```lua
local prflow = require('prflow')
prflow.start(ref) ; prflow.stop()
prflow.status()        -- { active, ready, branch, ref, base, mode, files = { { path, old_path, status, added, removed } } }
prflow.hunks(path)     -- hunks of one changed file
prflow.files() ; prflow.hunk() ; prflow.toggle_viewed()
prflow.range(mode, sha) ; prflow.mark_reviewed()
```

## How it works

- Base content comes from `git show <base>:<path>`, once per file, cached. Every hunk
  computation after that runs in-process (`vim.text.diff`), debounced 150 ms after edits.
- Rendering is extmarks only, in the `prflow` namespace; buffer text is never touched.
- A hunk's identity is a sha256 of its path, old lines and new lines, so editing a viewed
  hunk makes it unviewed again.
- State lives in `<git-dir>/prflow/state.json`, so each git worktree keeps its own.

## Development

```sh
make test                              # all specs (clones mini.nvim into deps/ on first run)
make test-file FILE=tests/test_m3_stream.lua
```

`:checkhealth prflow` checks the Neovim version, `git`, and that the base ref exists.
