EMACS ?= emacs
STRAIGHT ?= $(HOME)/.config/emacs/.local/straight/repos
# Directories holding transient (and its dependencies), yasnippet and
# package-lint.  Override STRAIGHT, or LOAD_PATH, when they live elsewhere:
#   make test STRAIGHT=~/.emacs.d/straight/repos
LOAD_PATH ?= -L . -L test -L $(STRAIGHT)/transient/lisp -L $(STRAIGHT)/compat \
	-L $(STRAIGHT)/yasnippet -L $(STRAIGHT)/cond-let -L $(STRAIGHT)/llama -L $(STRAIGHT)/package-lint

BATCH = $(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)'

.PHONY: all compile test checkdoc lint clean

all: compile checkdoc lint test

compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile commit-butler.el

test:
	$(BATCH) -l test/commit-butler-test.el -f ert-run-tests-batch-and-exit

checkdoc:
	$(BATCH) --eval '(defvar checkdoc-failed nil)' \
	  --eval '(advice-add (quote checkdoc-error) :after (lambda (&rest _) (setq checkdoc-failed t)))' \
	  --eval '(checkdoc-file "commit-butler.el")' \
	  --eval '(kill-emacs (if checkdoc-failed 1 0))'

lint:
	$(BATCH) --eval '(require (quote package-lint))' \
	  --eval '(setq package-user-dir (expand-file-name "elpa" temporary-file-directory))' \
	  --eval '(setq package-archives (quote (("gnu" . "https://elpa.gnu.org/packages/"))))' \
	  --eval '(package-initialize)' --eval '(package-refresh-contents)' \
	  --eval '(unless package-archive-contents (error "Could not download the package archives"))' \
	  --eval '(setq package-lint-main-file "commit-butler.el")' \
	  -f package-lint-batch-and-exit commit-butler.el

clean:
	rm -f *.elc test/*.elc
