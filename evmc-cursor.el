;;; evmc-cursor.el --- Fake cursor model -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; A fake cursor is a `evmc-cursor' struct.  Its position of record is the START
;; of its display overlay, which Emacs adjusts for us whenever the buffer
;; changes; nothing here ever stores a buffer location as an integer.

;;; Code:

(require 'cl-lib)
(require 'evmc-common)

(defconst evmc--overlay-priority 100
  "Priority of cursor overlays.
High enough to draw over `hl-line-mode' and the active region, which
would otherwise hide cursors on the current line.")

(cl-defstruct (evmc-cursor (:constructor evmc--make-cursor)
                           (:copier nil))
  "One fake cursor.
The cursor's position is not a slot, it is the `overlay''s start, so
that it self-adjusts when other cursors edit the buffer.  The OVERLAY
lives exactly as long as the cursor.  Pausing clears its display
properties but never deletes it.

A slot should exist only for state that the real cursor's turn would
change or consume before the fake cursors get theirs."
  overlay                 ; position of record, and the drawn cursor
  region-overlay          ; selection display, or nil
  mark                    ; marker or nil, this is never an integer
  mark-active
  last-command            ; per-cursor, gives repeat detection and goal column
  temporary-goal-column   ; previous command's intent, this is not derivable
  register                ; `evil-this-register', the "x prefix
  kill-ring
  kill-ring-yank-pointer) ; a cons INTO kill-ring, this travels with it

(defsubst evmc--cursor-point (cursor)
  "Return the buffer position of CURSOR, or nil if its overlay is dead."
  (overlay-start (evmc-cursor-overlay cursor)))

(defun evmc--make-cursor-overlay (pos)
  "Return a new unrendered cursor overlay at POS.
Both advance flags are set to nil so that the start and end stay pinned
together on a zero-length overlay.  The position update is always an
explicit `move-overlay' after replay.  `evaporate' is unset since
end-of-line cursors are zero-length and would evaporate."
  (let ((ov (make-overlay pos pos (current-buffer) nil nil)))
    (overlay-put ov 'evmc-cursor t)
    (overlay-put ov 'priority evmc--overlay-priority)
    ov))

(defun evmc--cursor-create (pos)
  "Return a new fake cursor at POS that inherits the real cursor's state.
The caller is responsible for adding it to `evmc-cursor-list'."
  (evmc--make-cursor
   :overlay (evmc--make-cursor-overlay pos)
   :mark (let ((m (mark-marker)))
           (when (marker-position m)
             (copy-marker m)))
   :mark-active mark-active
   :last-command last-command
   :temporary-goal-column temporary-goal-column
   :register evil-this-register
   ;; The following is shared with the globals on purpose
   ;; The pair stays consistent and diverge only once this cursor kills
   ;; something.
   :kill-ring kill-ring
   :kill-ring-yank-pointer kill-ring-yank-pointer))

(defun evmc--cursor-delete (cursor)
  "Delete CURSOR's overlays and detach its marker.
Detaching matters because every live marker is adjusted on every buffer change."
  (let ((ov (evmc-cursor-overlay cursor))
        (rov (evmc-cursor-region-overlay cursor))
        (mark (evmc-cursor-mark cursor)))
    (when (overlayp ov) (delete-overlay ov))
    (when (overlayp rov) (delete-overlay rov))
    (when (markerp mark) (set-marker mark nil))))

(defsubst evmc--coverable-p (pos)
  "Return non-nil when POS holds a character a cursor can be drawn over.
A newline cannot be drawn over, so we give it a face that extends the
highlight to the window edge.  This looks like a selection rather than a
cursor."
  (let ((ch (char-after pos)))
    (and ch (not (eq ch ?\n)))))

(defun evmc--render-cursor (cursor)
  "Draw CURSOR.
This covers the character at point where there is one, otherwise it
shows a one-space `after-string'.  This should be called after every
batch because a cursor can move between the two cases, or this should
delete the character it was covering, which collapses its own overlay
into nothing."
  (let* ((ov (evmc-cursor-overlay cursor))
         (pos (and (overlayp ov) (overlay-start ov))))
    (when pos
      (if (evmc--coverable-p pos)
          (progn
            (move-overlay ov pos (1+ pos))
            (overlay-put ov 'after-string nil)
            (overlay-put ov 'face 'evmc-cursor-face))
        (move-overlay ov pos pos)
        (overlay-put ov 'face nil)
        (overlay-put ov 'after-string
                     (propertize " " 'face 'evmc-cursor-face))))))

(defun evmc--render-region (cursor)
  "Draw or remove CURSOR's selection overlay.
One overlay should serve both selection models: Emacs' mark and Evil's
visual state.  Evil's character-wise visual selection includes the
character under point, Emacs' region does not, so the end differs by
one."
  (let* ((pos (evmc--cursor-point cursor))
         (mark (evmc-cursor-mark cursor))
         (mark-pos (and (markerp mark) (marker-position mark)))
         (visual (eq evil-state 'visual))
         (active (or (evmc-cursor-mark-active cursor) visual))
         (rov (evmc-cursor-region-overlay cursor)))
    (if (and pos mark-pos active)
        (let ((beg (min pos mark-pos))
              (end (if visual
                       (min (1+ (max pos mark-pos))
                            (point-max))
                     (max pos mark-pos))))
          (if (overlayp rov)
              (move-overlay rov beg end)
            (setq rov (make-overlay beg end (current-buffer) nil nil))
            (overlay-put rov 'evmc-region t)
            ;; Overlay is below the cursor so that the cursor stays visible in
            ;; its own selection
            (overlay-put rov 'priority (1- evmc--overlay-priority))
            (overlay-put rov 'face 'evmc-region-face)
            (setf (evmc-cursor-region-overlay cursor) rov)))
      (when (overlayp rov)
        (delete-overlay rov)
        (setf (evmc-cursor-region-overlay cursor) nil)))))

(defun evmc--unrender-cursor (cursor)
  "Stop drawing CURSOR without destroying it, essentially just pause it.
The overlay stays alive and keeps tracking the buffer so that resuming does
not need any stored position."
  (let ((ov (evmc-cursor-overlay cursor))
        (rov (evmc-cursor-region-overlay cursor)))
    (when (and (overlayp ov) (overlay-start ov))
      (overlay-put ov 'face nil)
      (overlay-put ov 'after-string nil)
      (move-overlay ov (overlay-start ov) (overlay-start ov)))
    (when (overlayp rov)
      (delete-overlay rov)
      (setf (evmc-cursor-region-overlay cursor) nil))))

(defun evmc--render-all ()
  "Redraw every cursor in the buffer, or hide them all when `evmc-frozen'."
  (dolist (cursor evmc-cursor-list)
    (if evmc-frozen
        (evmc--unrender-cursor cursor)
      (evmc--render-cursor cursor)
      (evmc--render-region cursor))))

(defun evmc--cursor-at (pos)
  "Return the fake cursor whose position is POS.
If nothing is found, return nil."
  (cl-find-if (lambda (cursor) (eql (evmc--cursor-point cursor) pos))
              evmc-cursor-list))

(defun evmc--prune-cursors ()
  "Drop cursors whose overlay no longer lives in this buffer.
Their markers and region overlays are released on the way out."
  (let (live)
    (dolist (cursor evmc-cursor-list)
      (if (evmc--cursor-point cursor)
          (push cursor live)
        (evmc--cursor-delete cursor)))
    (setq evmc-cursor-list (nreverse live))))

(defun evmc--sort-cursors ()
  "Sort cursors by ascending buffer position.
This function exists because a motion may move each cursor by a
different amount, so cursors overtake one another and the ordering has
to be re-established after every batch.  This assumes
`evmc--prune-cursors' has already run."
  (setq evmc-cursor-list
        (sort evmc-cursor-list
              (lambda (a b)
                (< (evmc--cursor-point a) (evmc--cursor-point b))))))

(defun evmc--dedup-cursors ()
  "Delete cursors sharing a position with an earlier cursor or point.
The survivor is the first in ascending order, the others are dropped.
Merging their state has no correct answer currently, so do it
predictably rather than cleverly.  Also the real cursor always wins;
a fake cursor left on top of point would replay every edit made at
the same place.
This assumes that the list is pruned and sorted."
  (let ((real (point))
        (prev nil)
        kept)
    (dolist (cursor evmc-cursor-list)
      (let ((pos (evmc--cursor-point cursor)))
        (if (or (and prev (= pos prev)) (= pos real))
            (evmc--cursor-delete cursor)
          (setq prev pos)
          (push cursor kept))))
    (setq evmc-cursor-list (nreverse kept))))

(defun evmc--normalize-cursors ()
  "Re-establish every invariant of `evmc-cursor-list', then redraw.
This is the only function that adds, removes, or reorders cursors during
a batch's aftermath; the batch itself iterates a snapshot and never
touches the list."
  (evmc--prune-cursors)
  (evmc--sort-cursors)
  (evmc--dedup-cursors)
  (evmc--render-all))

(defun evmc--cursors-create-at (positions)
  "Create fake cursors at POSITIONS, or create none at all.
Positions that are already occupied by a cursor or by point are skipped.
When the total exceeds `evmc-cursor-limit', nothing is created."
  (let ((total (+ (evmc-count-cursors) (length positions))))
    (when (> total evmc-cursor-limit)
      (user-error "evmc: %d cursors exceeds evmc-cursor-limit (%d)"
                  total evmc-cursor-limit)))
  (dolist (pos positions)
    (unless (or (= pos (point)) (evmc--cursor-at pos))
      (push (evmc--cursor-create pos) evmc-cursor-list)))
  (evmc--normalize-cursors))

(defun evmc-delete-all-cursors ()
  "Delete every fake cursor in the current buffer."
  (mapc #'evmc--cursor-delete evmc-cursor-list)
  (setq evmc-cursor-list nil))

(provide 'evmc-cursor)
;;; evmc-cursor.el ends here
