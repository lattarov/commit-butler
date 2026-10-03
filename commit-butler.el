;;; commit-butler.el --- Transient menu for Conventional Commits -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Victor Lattaro Volpini

;; Author: Victor Lattaro Volpini <victorlattaro@proton.me>
;; Maintainer: Victor Lattaro Volpini <victorlattaro@proton.me>
;; URL: https://github.com/lattarov/commit-butler
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (transient "0.7.0") (yasnippet "0.14.0"))
;; Keywords: vc
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Commit Butler helps writing commit messages that follow the
;; Conventional Commits specification (https://www.conventionalcommits.org):
;;
;;     <type>(<scope>)!: <description>
;;
;; `commit-butler-menu' is a transient menu where the commit type, the
;; optional scope and the breaking change flag are picked; a live
;; preview of the header (the `<type>(<scope>)!: ' part of the
;; message) is shown at the top.  RET inserts the whole message at
;; point: the header, with point on the description, then the body
;; and, for a breaking change, a `BREAKING CHANGE:' footer, reached
;; with TAB.  Because the choices are regular transient infix
;; arguments, they can be set for the session or saved across
;; sessions with the usual transient commands (C-x s, C-x C-s), and
;; option history works.
;;
;; The message is the yasnippet snippet named "Conventional Commit"
;; for `git-commit-mode', which sees the menu arguments as the
;; variables `type', `scope' and `breaking'.  A snippet of that name in
;; the user's own snippet directories replaces the one shipped in
;; snippets/.  `commit-butler-snippets-initialize' adds the shipped
;; snippets to yasnippet.
;;
;; `commit-butler-mode' is a minor mode meant for commit message buffers
;; that binds the menu:
;;
;;     (add-hook 'git-commit-setup-hook #'commit-butler-mode)

;;; Code:

(require 'cl-lib)
(require 'eieio)
(require 'subr-x)
(require 'transient)
(require 'yasnippet)

;;;; Customization

(defgroup commit-butler nil
  "Write Conventional Commits messages."
  :group 'vc
  :prefix "commit-butler-"
  :link '(url-link "https://www.conventionalcommits.org"))

(defcustom commit-butler-types
  '(("f" "feat")
    ("x" "fix")
    ("d" "docs")
    ("s" "style")
    ("r" "refactor")
    ("p" "perf")
    ("t" "test")
    ("b" "build")
    ("c" "ci")
    ("h" "chore")
    ("v" "revert"))
  "Commit types offered by `commit-butler-menu'.
Each element is a list (KEY TYPE), where KEY is the key that selects
TYPE in the menu.  KEY must not clash with the other keys of the menu:
\"o\", \"!\" and \"RET\"."
  :type '(repeat (list (string :tag "Key")
                       (string :tag "Type"))))

(defcustom commit-butler-default-type "feat"
  "Commit type selected when `commit-butler-menu' opens.
A value set or saved in the menu with `transient-set' or
`transient-save' takes precedence.  This type is also used when no
type is selected."
  :type 'string)

(defconst commit-butler-snippets-dir
  (expand-file-name "snippets"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the yasnippet snippets shipped with Commit Butler.
`commit-butler-snippets-initialize' adds it to `yas-snippet-dirs'.")

(defconst commit-butler--snippet-name "Conventional Commit"
  "Name of the `git-commit-mode' snippet inserted by the menu.")

;;;###autoload
(defun commit-butler-snippets-initialize ()
  "Add the snippets shipped with Commit Butler to yasnippet.
`commit-butler-snippets-dir' is added at the end of
`yas-snippet-dirs', so a snippet of the same name in another
directory takes precedence.  The snippets are reloaded if
`yas-global-mode' is already on."
  (add-to-list 'yas-snippet-dirs 'commit-butler-snippets-dir t)
  (when yas-global-mode
    (yas-reload-all)))

(defun commit-butler--snippet ()
  "Return the snippet of the commit message inserted by the menu.
This is the `git-commit-mode' snippet named
`commit-butler--snippet-name' when yasnippet has one loaded, and
otherwise the body of the snippet shipped in
`commit-butler-snippets-dir', read on each call.  The snippet sees
the menu arguments `type', `scope' and `breaking' as variables."
  (or (yas-lookup-snippet commit-butler--snippet-name 'git-commit-mode t)
      (let ((file (expand-file-name "git-commit-mode/conventional-commit"
                                    commit-butler-snippets-dir)))
        (unless (file-readable-p file)
          (user-error "Commit Butler snippet not found: %s" file))
        (with-temp-buffer
          (insert-file-contents file)
          (unless (re-search-forward "^# --\\s-*\n" nil t)
            (user-error "Commit Butler snippet has no \"# --\" line: %s" file))
          (buffer-substring-no-properties (point) (point-max))))))

;;;; Type/scope formatting

(defun commit-butler--snippet-env (args)
  "Return the snippet bindings for the transient ARGS."
  (let ((scope (transient-arg-value "--scope=" args)))
    `((type ,(or (transient-arg-value "--type=" args) commit-butler-default-type))
      (scope ,(and (stringp scope) (not (string-empty-p scope)) scope))
      (breaking ,(transient-arg-value "--breaking" args)))))

(defun commit-butler--message-build (args)
  "Return the header the snippet produces for ARGS, up to the description.
The snippet is expanded in a temporary buffer with the yasnippet hooks
off, as the menu calls this on each redisplay."
  (with-temp-buffer
    (let ((yas-minor-mode-hook nil)
          (yas-before-expand-snippet-hook nil)
          (yas-after-exit-snippet-hook nil))
      (commit-butler-insert args)
      (buffer-substring (point-min) (point)))))

;;;; Transient

(defclass commit-butler--type-switch (transient-switch)
  ((format :initform " %k %v"))
  "A switch selecting one commit type.
At most one switch of this class is on at a time.")

(cl-defmethod transient-infix-set :after ((obj commit-butler--type-switch) value)
  "Turn off every other commit type switch when OBJ is set to VALUE."
  (when value
    (dolist (other transient--suffixes)
      (when (and (not (eq other obj))
                 (cl-typep other 'commit-butler--type-switch))
        (transient-infix-set other nil)))))

(cl-defmethod transient-format-value ((obj commit-butler--type-switch))
  "Show the type of OBJ, highlighted when it is the selected type."
  (let ((type (string-remove-prefix "--type=" (oref obj argument))))
    (propertize type
                'face (if (equal type (commit-butler--selected-type))
                          'transient-value
                        'transient-inactive-value))))

(defun commit-butler--selected-type ()
  "Return the type selected in the active menu, or the default type."
  (or (transient-arg-value "--type=" (transient-get-value))
      commit-butler-default-type))

(defun commit-butler--type-suffixes (_children)
  "Return the commit type switches built from `commit-butler-types'."
  (transient-parse-suffixes
   'commit-butler-menu
   (mapcar (pcase-lambda (`(,key ,type))
             (list key type (concat "--type=" type)
                   :class 'commit-butler--type-switch))
           commit-butler-types)))

(defun commit-butler--preview ()
  "Return the type/scope preview shown at the top of the menu."
  (concat "Preview: "
          (propertize (commit-butler--message-build (transient-get-value))
                      'face 'transient-value)
          "[description]"))

;;;###autoload (autoload 'commit-butler-menu "commit-butler" nil t)
(transient-define-prefix commit-butler-menu ()
  "Build a Conventional Commits type/scope and insert it at point."
  :value (lambda () (list (concat "--type=" commit-butler-default-type)))
  [:description commit-butler--preview
                ["Commit type"
                 :class transient-column
                 :setup-children commit-butler--type-suffixes]
                ["Options"
                 ("o" "Scope"           "--scope=")
                 ("!" "Breaking change" "--breaking")]
                ["Actions"
                 ("RET" "Insert" commit-butler-insert)]])

;;;###autoload
(defun commit-butler-insert (&optional args)
  "Expand the commit message snippet at point for ARGS.
ARGS are the arguments of `commit-butler-menu'.  This turns on
`yas-minor-mode' in the current buffer if it is off, as yasnippet
needs it to expand the snippet and to move between its fields."
  (interactive (list (transient-args 'commit-butler-menu)))
  (let ((snippet (commit-butler--snippet)))
    (unless yas-minor-mode
      (yas-minor-mode 1))
    (yas-expand-snippet snippet nil nil (commit-butler--snippet-env args))))

;;;; Minor mode

(defvar commit-butler-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c ,") #'commit-butler-menu)
    map)
  "Keymap for `commit-butler-mode'.")

;;;###autoload
(define-minor-mode commit-butler-mode
  "Minor mode binding `commit-butler-menu' in commit message buffers.
It also activates the `git-commit-mode' snippets in the buffer: Magit's
`git-commit-mode' is a minor mode, so yasnippet does not look up its
snippets by itself.

\\{commit-butler-mode-map}"
  :lighter nil
  :keymap commit-butler-mode-map
  (if commit-butler-mode
      (yas-activate-extra-mode 'git-commit-mode)
    (yas-deactivate-extra-mode 'git-commit-mode)))

(provide 'commit-butler)
;;; commit-butler.el ends here
