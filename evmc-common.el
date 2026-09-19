;;; evmc-common.el --- Shared state for evil-multiple-cursors -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Customization group, faces, and buffer-local state shared by every
;; evil-multiple-cursors library.  Everything here is loaded first and
;; depends on nothing but Evil.

;;; Code:

(require 'evil)

(defgroup evmc nil
  "Multiple cursors that speak evil."
  :group 'evil
  :prefix "evmc-")

(defcustom evmc-cursor-limit 128
  "Refuse to create more than this many fake cursors.
Replaying a command is linear in the cursor count, so a runaway
`evmc-make-all-cursors' on a large buffer can wedge Emacs."
  :type 'integer)

(defcustom evmc-verbose nil
  "When non-nil, echo cursor count changes in the minibuffer."
  :type 'boolean)

(defface evmc-cursor-face
  '((t :inverse-video t))
  "Face for the block drawn at each fake cursor.

By default, this swaps the underlying text's own colors, rather than
inheriting `cursor', keeps fake cursors legible under any theme in both
GUI and terminal frames, and keeps them visually distinct from the real
cursor.")

(defface evmc-region-face
  '((t :inherit region))
  "Face for the visual selection of each fake cursor.")

(defvar-local evmc-cursor-list nil
  "Fake cursors in this buffer, ordered by buffer position.
The real cursor (point) is never a member of this list.")

(defvar-local evmc-frozen nil
  "When non-nil, fake cursors are displayed but do not replay commands.")

(defvar evmc-executing-command nil
  "Non-nil while a command is being replayed at a fake cursor.

Replay re-runs the user's command once per fake cursor.  Emacs cannot
tell those replays apart from real user input, so `post-command-hook'
fires after each one.  Our replay driver lives in that hook, so it must
return immediately when this flag is set; otherwise every replay would
kick off a further round of replays and recurse.

Read this as \"the current command is synthetic\". Any code that should
only react to genuine keystrokes should test this flag.")

(defun evmc-count-cursors ()
  "Return the number of cursors, real one included."
  (1+ (length evmc-cursor-list)))

(defun evmc-message (format-string &rest args)
  "Echo FORMAT-STRING with ARGS when `evmc-verbose' is non-nil."
  (when evmc-verbose
    (apply #'message (concat "evmc: " format-string) args)))

(provide 'evmc-common)
;;; evmc-common.el ends here
