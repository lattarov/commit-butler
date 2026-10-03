;;; commit-butler-test.el --- Tests for commit-butler -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with: make test

;;; Code:

(require 'ert)
(require 'commit-butler)

(defmacro commit-butler-test--with-defaults (&rest body)
  "Run BODY with every Commit Butler option at its default value."
  (declare (indent 0))
  `(let ((commit-butler-default-type "feat"))
     ,@body))

(ert-deftest commit-butler-test-type-only ()
  (commit-butler-test--with-defaults
   (should (equal (commit-butler--message-build '("--type=fix")) "fix: "))))

(ert-deftest commit-butler-test-default-type ()
  (commit-butler-test--with-defaults
   (should (equal (commit-butler--message-build nil) "feat: "))))

(ert-deftest commit-butler-test-all-fields ()
  (commit-butler-test--with-defaults
   (should (equal (commit-butler--message-build
                   '("--type=refactor" "--scope=api" "--breaking"))
                  "refactor(api)!: "))))

(ert-deftest commit-butler-test-empty-strings-are-omitted ()
  (commit-butler-test--with-defaults
   (should (equal (commit-butler--message-build '("--type=docs" "--scope="))
                  "docs: "))))

(ert-deftest commit-butler-test-insert ()
  (commit-butler-test--with-defaults
   (with-temp-buffer
     (commit-butler-insert '("--type=fix" "--scope=x"))
     (should (equal (buffer-string) "fix(x): \n\n\n\n"))
     (should (= (point) (1+ (length "fix(x): ")))))))

(ert-deftest commit-butler-test-insert-breaking ()
  (commit-butler-test--with-defaults
   (with-temp-buffer
     (commit-butler-insert '("--type=feat" "--breaking"))
     (should (equal (buffer-string) "feat!: \n\n\n\nBREAKING CHANGE: ")))))

(defmacro commit-butler-test--with-menu (&rest body)
  "Run BODY with `commit-butler-menu' active and no set or saved value."
  (declare (indent 0))
  `(commit-butler-test--with-defaults
    (let ((transient-values nil))
      (with-temp-buffer
        (transient-setup 'commit-butler-menu)
        (unwind-protect (progn ,@body)
          (transient-quit-one))))))

(defun commit-butler-test--type-switch (type)
  "Return the switch of the active menu that selects TYPE."
  (cl-find (concat "--type=" type) transient--suffixes
           :key (lambda (obj)
                  (and (cl-typep obj 'commit-butler--type-switch)
                       (oref obj argument)))
           :test #'equal))

(ert-deftest commit-butler-test-menu-default-value ()
  (commit-butler-test--with-menu
   (should (equal (transient-get-value) '("--type=feat")))))

(ert-deftest commit-butler-test-menu-one-type-at-a-time ()
  (commit-butler-test--with-menu
   (transient-infix-set (commit-butler-test--type-switch "fix") "--type=fix")
   (should (equal (transient-get-value) '("--type=fix")))
   (should (equal (substring-no-properties (commit-butler--preview))
                  "Preview: fix: [description]"))))

(ert-deftest commit-butler-test-menu-highlights-selected-type ()
  (commit-butler-test--with-menu
   (should (eq (get-text-property 0 'face (transient-format-value
                                           (commit-butler-test--type-switch "feat")))
               'transient-value))
   (should (eq (get-text-property 0 'face (transient-format-value
                                           (commit-butler-test--type-switch "fix")))
               'transient-inactive-value))))

(defun commit-butler-test--unload-snippets ()
  "Unload the snippets loaded by a test.
The snippets are reloaded from an empty directory, as `yas-reload-all'
prompts for one when `yas-snippet-dirs' is nil."
  (let ((empty (make-temp-file "commit-butler-test-" t)))
    (setq yas-snippet-dirs (list empty))
    (yas-reload-all)
    (delete-directory empty)))

(ert-deftest commit-butler-test-missing-snippet ()
  (cl-letf ((commit-butler-snippets-dir (make-temp-name "/nonexistent-"))
            ((symbol-function 'yas-lookup-snippet) #'ignore))
    (with-temp-buffer
      (should-error (commit-butler-insert '("--type=fix")) :type 'user-error)
      (should (equal (buffer-string) "")))))

(ert-deftest commit-butler-test-user-snippet-overrides ()
  (let* ((dir (make-temp-file "commit-butler-test-" t))
         (yas-snippet-dirs (list dir))
         (yas-minor-mode-hook nil))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "git-commit-mode" dir))
          (with-temp-file (expand-file-name "git-commit-mode/mine" dir)
            (insert "# name: Conventional Commit\n# --\nmine `type`: $0"))
          (commit-butler-snippets-initialize)
          (should (equal yas-snippet-dirs (list dir 'commit-butler-snippets-dir)))
          (yas-reload-all)
          (with-temp-buffer
            (text-mode)
            (yas-minor-mode 1)
            (commit-butler-mode 1)
            (commit-butler-insert '("--type=fix"))
            (should (equal (buffer-string) "mine fix: "))))
      (delete-directory dir t)
      (commit-butler-test--unload-snippets))))

(ert-deftest commit-butler-test-preview-runs-no-hooks ()
  (commit-butler-test--with-defaults
   (let* ((ran nil)
          (yas-before-expand-snippet-hook (list (lambda () (setq ran t)))))
     (should (equal (commit-butler--message-build '("--type=fix")) "fix: "))
     (should-not ran))))

(ert-deftest commit-butler-test-type-suffixes ()
  (let ((commit-butler-types '(("f" "feat") ("x" "fix"))))
    (should (= (length (commit-butler--type-suffixes nil)) 2))))

(provide 'commit-butler-test)
;;; commit-butler-test.el ends here
