# evil-multiple-cursors (`evmc`)

Multiple cursors for Emacs that understand Evil's modal editing: operators,
text objects, registers and insert-state replay.


## Relationship to evil-mc

This is an independent implementation, written from scratch. Gabriel Adomnicai's
[evil-mc](https://github.com/gabesoft/evil-mc) solves the same problem and is
the mature option; `evmc` borrows its overall shape (fake cursors as overlays, a
command handler table, insert-state keystroke replay) but shares no code. The
`evmc-` prefix keeps both installable side by side.


## Install

Do a git clone, then:

```elisp
(add-to-list 'load-path "/path/to/evil-multiple-cursors")
(require 'evmc)
(add-hook 'prog-mode-hook #'evmc-mode)
```

## Development

Requires [Eldev](https://emacs-eldev.github.io/eldev/). Dependencies resolve
into a project-local `.eldev/` sandbox, so your own Emacs config is not
involved.

```sh
eldev compile   # byte-compile; warnings are errors
eldev lint      # checkdoc + package-lint
eldev test      # ERT
```

CI runs exactly these three on Emacs 29.1 and 30.1.


## Layout

|File            |Role                                          |
|----------------|----------------------------------------------|
|`evmc.el`       |Entry point: minor mode, command map          |
|`evmc-common.el`|Customization group, faces, buffer-local state|


## Keybindings

All are currently under `gr` in normal and visual state.
