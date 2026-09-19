;;; evmc.el --- Multiple cursors for Evil -*- lexical-binding: t; -*-

;; Author: Eyoel Tesfu <eyoelytesfu@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (evil "1.15.0"))
;; Keywords: convenience, editing, emulations
;; URL: https://www.github.com/eyoelyt/evmc
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Entry point for evil-multiple-cursors: the minor mode, the `gr' and the
;; command map.  Cursor state lives in `evmc-common', the replay driver in
;; `evmc-command', cursor creation in `evmc-cursor-make'.

;;; Code:

(require 'evil)
(require 'evmc-common)

(defvar evmc-command-map (make-sparse-keymap)
  "Keymap of cursor-creation commands.
Reachable in normal and visual state while `evmc-mode' is enabled.
Entries are added by `evmc-cursor-make'.")

(defvar evmc-mode-map
  (let ((map (make-sparse-keymap)))
    (evil-define-key* '(normal visual) map (kbd "gR") evmc-command-map) ; REVIEW: factor out "gR" into a separate defcustom?
    map)
  "Keymap enabled by `evmc-mode'.")

;;;###autoload
(define-minor-mode evmc-mode
  "Edit with multiple Evil cursors in the current buffer.

Enabling the mode only makes the keymap prefix available; no cursors
exist until one of its commands creates them.  Disabling it discards
every fake cursor in the buffer."
  :lighter " evmc"
  :keymap evmc-mode-map
  :group 'evmc
  ;; The replay driver's `post-command-hook' entry is installed here
  ;; once `evmc-command' exists; teardown must also delete every cursor
  ;; overlay.
  (unless evmc-mode
    (setq evmc-frozen nil)))

(provide 'evmc)
;;; evmc.el ends here
