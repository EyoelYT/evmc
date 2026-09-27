# evmc design decisions

Decisions, with the reasoning that produced them.  Reversal is fine; reversal
without reading the reason is not.

## Decision log

|# |Decision                                                                               |Key reason                                                                                                            |
|--|---------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
|1 |Cursor is a mutable `cl-defstruct`; position lives in its display overlay              |Self-adjusting position, compile-checked field names, explicit mutation                                               |
|2 |Overlay lives exactly as long as the cursor; pause clears display properties only      |A cursor without an overlay has no position; stashing one elsewhere reintroduces staleness                            |
|3 |Render hybrid: cover the character mid-line, `after-string " "` at EOL/empty/EOB       |Mid-line `after-string` shifts the rest of the line one column per cursor                                             |
|4 |`overlay-start` is authoritative; `overlay-end` is display-only, recomputed each render|Deleting the covered character collapses the overlay; the cursor must survive its own edit                            |
|5 |`make-overlay` with both advance flags nil; position written explicitly post-replay    |Mixed flags let start outrun end on zero-length (EOL) overlays                                                        |
|6 |Replay forward, ascending position; real cursor's point/mark held in markers           |The real cursor already ran first, so order can only buy predictability — and the real point goes stale like any other|
|7 |Post-batch pipeline: prune → sort → dedup → render; list never mutated mid-batch       |Motions let cursors overtake each other, so the sort invariant must be re-established, not maintained                 |
|8 |Dedup keeps the first in ascending order; the real cursor always wins                  |Stacked cursors double every edit forever; merging two selections has no correct answer                               |
|9 |One undo step per batch, pointer captured in `pre-command-hook`                        |The real cursor's edit is already on the undo list before `post-command-hook` runs                                    |
|10|`evmc-cursor-limit` enforced at creation only, atomically                              |Refusing at replay leaves visible cursors that silently do nothing                                                    |

## 8. Which commands get replayed

Default-allow, no whitelist.  Dispatch is tried in three tiers.

**Tier 1 — replay the command symbol.**  `call-interactively` at each cursor.
Covers motions and in-buffer edits, Emacs and Evil alike, with no registration.

**Tier 2 — replay the key sequence.**  Commands that consume extra input
(`f`, `t`, `F`, `T`, `r`, `zap-to-char`) cannot be replayed as a symbol: re-running
them reads from the input stream and eats the user's *next* keystrokes.  Replay
`(this-command-keys)` instead — it contains the consumed character — through the
same machinery as `evmc-apply-macro-at-cursors` (§10), at single-command
granularity.

**Tier 3 — skip and blacklist.**  Detected at runtime, not predicted:

```elisp
(let ((inhibit-interaction t)          ; Emacs 28+
      (evmc-executing-command t))
  (dolist (cursor cursors)
    (condition-case err
        (evmc--replay cursor)
      (inhibited-interaction
       (evmc--session-blacklist-add this-command)
       (evmc--log "skipped %S: reads input" this-command))
      (error
       (evmc--log "cursor %S failed: %S" cursor err)))))
```

### Rejected: static `interactive-form` inspection

An earlier draft scanned the interactive spec for the letters `s f F b B n`.
It fails twice over:

- A string spec is the old style.  `find-file`, `query-replace`, `goto-line`,
  and every `completing-read`- or transient-based command use a Lisp form
  (`(interactive (list (read-file-name ...)))`), which the scan reads as safe.
  Catching those statically means walking the form for `read-*` calls — a
  heuristic arms race.
- It says nothing about `read-char`/`read-key` commands.  Those never prompt;
  they steal input.  Replaying `f` at N cursors consumes the next N keystrokes.

`inhibit-interaction` covers both families by trying rather than predicting, and
the blacklist builds itself with no prompts and no list to maintain.

### Still an explicit list

Commands that are dangerous but never read input, so runtime detection cannot
see them: `undo`, `save-buffer`, `isearch-*`, window and buffer switching, and
evmc's own cursor-creation commands (infinite regress).

### Accepted failure modes

- Partial application: the real cursor ran, the fakes were skipped.  One
  grouped `u` reverts it.
- A command that mutates before reading leaves a partial edit at that cursor.
- A command that traps errors internally may swallow `inhibited-interaction`
  and behave oddly.

`evmc-prompt-for-unknown-commands` (mc-style ask-once) exists but defaults to
nil: prompts mid-edit break flow worse than a logged skip.
