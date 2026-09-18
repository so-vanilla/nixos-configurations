;;; init.el --- My terminal Emacs configuration -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(let ((lisp-directory (expand-file-name "lisp" user-emacs-directory)))
  ;; Home Manager deploys this directory recursively.  Keep both the root
  ;; and ADE's adapter directory on `load-path' so `ade.el' may be supplied
  ;; either beside the subdirectory or by the ADE source bundle.
  (add-to-list 'load-path lisp-directory)
  (add-to-list 'load-path (expand-file-name "ade" lisp-directory)))

(defmacro when-darwin (&rest body)
  (when (eq system-type 'darwin)
    `(progn ,@body)))

(let ((private-hosts '("vanilla" "chocolate"))
      (current-host (system-name)))
  (defvar is-private-host
    (not (null (member current-host private-hosts)))))

(load (expand-file-name "private.el" user-emacs-directory) t)

(require 'leaf)
(require 'leaf-keywords)
(leaf-keywords-init)

(require 'ade-platform)
(ade-platform-initialize)

(leaf leaf-convert)
(leaf leaf-tree)
(leaf hydra)

(add-hook 'prog-mode-hook
          (lambda ()
            (setq-local show-trailing-whitespace t)))

(setq frame-title-format '("%b")
      ring-bell-function #'ignore
      use-file-dialog nil
      use-short-answers t
      create-lockfiles t
      tab-width 4
      gc-cons-threshold 10000000
      read-process-output-max 1048576
      enable-recursive-minibuffers t
      system-time-locale "C"
      treesit-auto-install-grammar 'never
      treesit-extra-load-path (list (expand-file-name "tree-sitter-grammars" user-emacs-directory))
      treesit-font-lock-level 4
      major-mode-remap-alist '((sh-mode . bash-ts-mode)
                               (bash-mode . bash-ts-mode)
                               (dockerfile-mode . dockerfile-ts-mode)
                               (go-mode . go-ts-mode)
                               (java-mode . java-ts-mode)
                               (js-json-mode . json-ts-mode)
                               (lua-mode . lua-ts-mode)
                               (nix-mode . nix-ts-mode)
                               (python-mode . python-ts-mode)
                               (toml-mode . toml-ts-mode)
                               (yaml-mode . yaml-ts-mode)))

(leaf startup
  :tag "builtin"
  :custom
  ((inhibit-splash-screen . t)
   (inhibit-startup-screen . t)
   (inhibit-startup-buffer-menu . t)))

(leaf files
  :tag "builtin"
  :custom
  ((make-backup-files . nil)
   (backup-inhibited . nil)))

(leaf savehist
  :tag "builtin"
  :global-minor-mode savehist-mode
  :custom
  ((history-length . 500)
   (savehist-autosave-interval . 300)
   (savehist-additional-variables . '(search-ring regexp-search-ring compile-history))))

(leaf uniquify
  :tag "builtin"
  :require t
  :custom
  ((uniquify-buffer-name-style . 'forward)
   (uniquify-separator . "/")
   (uniquify-after-kill-buffer-p . t)
   (uniquify-ignore-buffers-re . "^\\*")))

(leaf simple
  :tag "builtin"
  :preface
  (defun my/clipboard-copy-with-pbcopy (text)
    (let ((process-connection-type nil))
      (let ((proc (start-process "pbcopy" "*Messages*" "pbcopy")))
        (process-send-string proc text)
        (process-send-eof proc))))

  (defun my/clipboard-paste-with-pbpaste ()
    (shell-command-to-string "pbpaste"))

  (defun my/clipboard-copy-with-wl-copy (text)
    (let* ((default-directory "/")
           (proc (make-process :name "wl-copy"
                               :buffer nil
                               :command '("wl-copy" "-n")
                               :connection-type 'pipe
                               :noquery t)))
      (process-send-string proc text)
      (process-send-eof proc)))

  (defun my/clipboard-paste-with-wl-paste ()
    (let ((default-directory "/"))
      (with-temp-buffer
        (call-process "wl-paste" nil t nil "-n" "-t" "text/plain;charset=utf-8")
        (unless (= (point-min) (point-max))
          (buffer-string)))))

  (defun my/clipboard-copy-text (text)
    "Copy TEXT to the system clipboard without touching the kill ring."
    (cond
     ((and (eq system-type 'darwin) (executable-find "pbcopy"))
      (my/clipboard-copy-with-pbcopy text))
     ((executable-find "wl-copy")
      (my/clipboard-copy-with-wl-copy text))
     (t
      (user-error "No system clipboard copy command available"))))

  (defun my/clipboard-paste-text ()
    "Return text from the system clipboard without touching the kill ring."
    (cond
     ((and (eq system-type 'darwin) (executable-find "pbpaste"))
      (my/clipboard-paste-with-pbpaste))
     ((executable-find "wl-paste")
      (my/clipboard-paste-with-wl-paste))
     (t
      (user-error "No system clipboard paste command available"))))

  (defun my/clipboard-copy-region (beg end)
    "Copy the active region to the system clipboard only."
    (interactive "r")
    (unless (use-region-p)
      (user-error "No active region"))
    (my/clipboard-copy-text (buffer-substring-no-properties beg end))
    (deactivate-mark)
    (message "Copied region to system clipboard"))

  (defun my/clipboard-yank ()
    "Insert text from the system clipboard without using the kill ring."
    (interactive)
    (let ((text (my/clipboard-paste-text)))
      (if (and text (< 0 (length text)))
          (insert text)
        (message "System clipboard is empty"))))

  (defun my-move-beginning-of-line ()
    "Move point to indentation, or to beginning of line if already there."
    (interactive "^")
    (let ((orig-point (point)))
      (back-to-indentation)
      (when (= orig-point (point))
        (move-beginning-of-line 1))))

  (defun my-undo ()
    (interactive)
    (undo)
    (hydra-undo/body))

  (defun my-redo ()
    (interactive)
    (undo-redo)
    (hydra-undo/body))
  :hook
  ((before-save-hook . delete-trailing-whitespace))
  :custom
  ((indent-tabs-mode . nil)
   (select-active-regions . nil))
  :config
  (setq interprogram-cut-function nil
        interprogram-paste-function nil
        save-interprogram-paste-before-kill nil
        select-enable-clipboard nil
        select-enable-primary nil)
  :bind
  (("C-x u" . my-undo)
   ("C-x r" . my-redo)
   ("C-a" . my-move-beginning-of-line)
   ("M-C-w" . my/clipboard-copy-region)
   ("M-C-y" . my/clipboard-yank))
  :hydra
  ((hydra-undo
    (:hint nil)
    "
^Undo^
^^-----------
_u_: undo
_r_: redo
"
    ("u" undo)
    ("r" undo-redo)
    ("C-m" nil :exit t)
    ("q" nil :exit t))))

(leaf warning
  :tag "builtin"
  :custom
  ((warning-minimum-level . :error)))

(leaf mule-cmds
  :tag "builtin"
  :bind
  (("C-\\" . nil)
   (mule-keymap
    ("C-\\" . nil))))

(leaf battery
  :tag "builtin"
  :global-minor-mode display-battery-mode)

(leaf time
  :tag "builtin"
  :global-minor-mode display-time-mode
  :custom
  ((display-time-24hr-format . t)
   (display-time-default-load-average . nil)))

(leaf text-mode
  :tag "builtin"
  :custom
  (text-mode-ispell-word-completion . nil))

(leaf help
  :tag "builtin"
  :bind
  (("C-h K" . describe-keymap)))

(leaf hl-line
  :tag "builtin"
  :global-minor-mode global-hl-line-mode)

(leaf which-key
  :tag "builtin"
  :global-minor-mode which-key-mode)

(leaf subr
  :tag "builtin"
  :config
  (keyboard-translate ?\C-h ?\C-?))

(leaf autorevert
  :tag "builtin"
  :global-minor-mode global-auto-revert-mode)

(leaf editorconfig
  :tag "builtin"
  :global-minor-mode editorconfig-mode)

(leaf delsel
  :tag "builtin"
  :global-minor-mode delete-selection-mode)

(leaf window
  :tag "builtin"
  :custom
  ((split-width-threshold . 160)
   (split-height-threshold . 80)
   (display-buffer-base-action
    . '((display-buffer-reuse-window display-buffer-same-window)
        (reusable-frames . t)))))

(leaf isearch
  :tag "builtin"
  :custom
  ((isearch-allow-scroll . t)))

(leaf winner
  :tag "builtin"
  :global-minor-mode winner-mode
  :custom
  ((winner-dont-bind-my-keys . t)))

(leaf avy
  :bind
  (("C-;" . avy-goto-char-in-line)
   ("C-/" . avy-goto-char-timer)
   ("M-/" . avy-goto-end-of-line)
   ("M-?" . avy-goto-line)))

(leaf elec-pair
  :tag "builtin"
  :global-minor-mode electric-pair-mode
  :hook
  ((minibuffer-mode-hook . (lambda ()
                             (unless (eq this-command 'eval-expression)
                               (electric-pair-local-mode 0))))))

(leaf paren
  :tag "builtin"
  :global-minor-mode show-paren-mode
  :custom
  (show-paren-style 'mixed))

(leaf puni
  :global-minor-mode puni-global-mode
  :bind
  ((puni-mode-map
    ("C-k" . puni-kill-line)
    ("M-C-d" . puni-backward-kill-word)
    ("M-C-p" . hydra-puni/body)))
  :hydra
  ((hydra-puni
    (:hint nil)
    "
^Delete^        ^Move^
^^--------------^^-------------------
_C-w_: squeeze  _]_: slurp-forward
_s_: splice     _}_: barf-forward
                _[_: slurp-backward
                _{_: barf-backward
"
    ("C-w" puni-squeeze)
    ("s" puni-splice)
    ("]" puni-slurp-forward)
    ("}" puni-barf-forward)
    ("[" puni-slurp-backward)
    ("{" puni-barf-backward)
    ("C-m" nil :exit t)
    ("q" nil :exit t))))

(leaf rainbow-delimiters
  :hook
  ((prog-mode-hook . rainbow-delimiters-mode)))

(leaf windmove
  :tag "builtin"
  :bind
  (("C-x o" . hydra-windmove/body))
  :hydra
  ((hydra-windmove
    (:hint nil)
    "
^Direction^
^^-----------^Layout^
_C-f_: right
_C-b_: left
_C-p_: up
_C-n_: down
^^           _u_: undo
^^           _r_: redo
"
    ("C-f" windmove-right)
    ("C-b" windmove-left)
    ("C-p" windmove-up)
    ("C-n" windmove-down)
    ("u" winner-undo)
    ("r" winner-redo)
    ("C-m" nil :exit t)
    ("q" nil :exit t))))

(leaf magit
  :bind
  (("C-x g" . magit-status)))

(leaf smerge-mode
  :tag "builtin"
  :preface
  (defun my/smerge-keep-upper-all ()
    "Keep upper for all conflicts in the buffer."
    (interactive)
    (save-excursion
      (goto-char (point-min))
      (let ((count 0))
        (condition-case nil
            (while t
              (smerge-next)
              (smerge-keep-upper)
              (cl-incf count))
          (error nil))
        (message "Resolved %d conflicts with upper" count))))

  (defun my/smerge-keep-lower-all ()
    "Keep lower for all conflicts in the buffer."
    (interactive)
    (save-excursion
      (goto-char (point-min))
      (let ((count 0))
        (condition-case nil
            (while t
              (smerge-next)
              (smerge-keep-lower)
              (cl-incf count))
          (error nil))
        (message "Resolved %d conflicts with lower" count))))
  :hydra
  ((hydra-smerge
    (:hint nil)
    "
^Move^          ^Keep^              ^All^               ^Other^
^^--------------^^------------------^^------------------^^-----------
_n_: next       _u_: upper          _U_: upper all      _e_: ediff
_p_: prev       _l_: lower          _L_: lower all      _r_: resolve
^^              _b_: base           ^^                  _R_: refine
^^              _a_: all            ^^                  _c_: combine
^^              _RET_: current
"
    ("n" smerge-next)
    ("p" smerge-prev)
    ("u" smerge-keep-upper)
    ("l" smerge-keep-lower)
    ("b" smerge-keep-base)
    ("a" smerge-keep-all)
    ("RET" smerge-keep-current)
    ("U" my/smerge-keep-upper-all :exit t)
    ("L" my/smerge-keep-lower-all :exit t)
    ("e" smerge-ediff :exit t)
    ("r" smerge-resolve)
    ("R" smerge-refine)
    ("c" smerge-combine-with-next)
    ("q" nil :exit t)))
  :config
  (with-eval-after-load 'smerge-mode
    (setcdr smerge-mode-map nil)
    (define-key smerge-mode-map (kbd "C-c ^") #'hydra-smerge/body)))

(leaf vertico
  :global-minor-mode vertico-mode)

(leaf orderless
  :custom
  ((completion-styles . '(orderless basic))
   (completion-category-overrides . '((file (style basic partial-completion))))
   (orderless-matching-styles . '(orderless-literal
                                  orderless-prefixes
                                  orderless-initialism
                                  orderless-regexp))))

(leaf marginalia
  :global-minor-mode marginalia-mode)

(leaf consult
  :bind
  (([remap switch-to-buffer] . consult-buffer)
   ([remap imenu] . consult-imenu)
   ([remap goto-line] . consult-goto-line)
   ("C-s" . consult-line)
   ("C-M-s" . consult-ripgrep)
   (minibuffer-mode-map
    ("C-r" . consult-history))))

(leaf embark
  :bind
  (("M-." . embark-dwin)
   ("C-." . embark-act)))

(leaf embark-consult
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

(leaf xref
  :tag "builtin"
  :custom
  ((xref-search-program . 'ripgrep)
   (xref-show-xrefs-function . #'consult-xref)
   (xref-show-definitions-function . #'consult-xref)))

(leaf corfu
  :global-minor-mode global-corfu-mode
  :custom
  ((corfu-auto . t)
   (corfu-auto-delay . 0.2)
   (corfu-auto-prefix . 2)
   (corfu-preview-current . nil)
   (corfu-cycle . t)))

(leaf cape
  :config
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-elisp-block)
  (add-to-list 'completion-at-point-functions #'cape-elisp-symbol))

(leaf yasnippet
  :global-minor-mode yas-global-mode)

(leaf eldoc
  :tag "builtin"
  :global-minor-mode global-eldoc-mode
  :custom
  ((eldoc-idle-delay . 0.6)
   (eldoc-echo-area-use-multiline-p . nil)))

(leaf eglot
  :tag "builtin"
  :hook
  ((bash-ts-mode-hook . eglot-ensure)
   (dockerfile-ts-mode-hook . eglot-ensure)
   (go-ts-mode-hook . eglot-ensure)
   (go-mod-ts-mode-hook . eglot-ensure)
   (java-ts-mode-hook . eglot-ensure)
   (json-ts-mode-hook . eglot-ensure)
   (lua-ts-mode-hook . eglot-ensure)
   (markdown-ts-mode-hook . eglot-ensure)
   (nix-ts-mode-hook . eglot-ensure)
   (python-ts-mode-hook . eglot-ensure)
   (terraform-mode-hook . eglot-ensure)
   (hcl-mode-hook . eglot-ensure)
   (toml-ts-mode-hook . eglot-ensure)
   (yaml-ts-mode-hook . eglot-ensure))
  :custom
  ((eglot-autoshutdown . t)
   (eglot-sync-connect . 0)
   (eglot-events-buffer-size . 0)
   (eglot-confirm-server-initiated-edits . nil))
  :config
  (define-prefix-command 'my/eglot-prefix-map)
  (global-set-key (kbd "M-l") 'my/eglot-prefix-map)
  (define-key my/eglot-prefix-map (kbd "d") #'xref-find-definitions)
  (define-key my/eglot-prefix-map (kbd "r") #'xref-find-references)
  (define-key my/eglot-prefix-map (kbd "a") #'eglot-code-actions)
  (define-key my/eglot-prefix-map (kbd "R") #'eglot-rename)
  (define-key my/eglot-prefix-map (kbd "f") #'eglot-format)
  (dolist (entry '(((bash-ts-mode sh-mode) . ("bash-language-server" "start"))
                   ((dockerfile-ts-mode) . ("docker-langserver" "--stdio"))
                   ((go-ts-mode go-mod-ts-mode) . ("gopls"))
                   ((java-ts-mode) . ("jdtls"))
                   ((json-ts-mode) . ("vscode-json-language-server" "--stdio"))
                   ((lua-ts-mode) . ("lua-language-server"))
                   ((markdown-ts-mode markdown-mode) . ("marksman"))
                   ((nix-ts-mode nix-mode) . ("nixd"))
                   ((python-ts-mode python-mode) . ("basedpyright-langserver" "--stdio"))
                   ((terraform-mode hcl-mode) . ("terraform-ls" "serve"))
                   ((toml-ts-mode) . ("taplo" "lsp" "stdio"))
                   ((yaml-ts-mode) . ("yaml-language-server" "--stdio"))))
    (add-to-list 'eglot-server-programs entry)))

(leaf eglot-booster
  :after eglot
  :global-minor-mode eglot-booster-mode)

(leaf flycheck
  :global-minor-mode global-flycheck-mode
  :custom
  ((flycheck-check-syntax-automatically . '(save mode-enabled idle-change))
   (flycheck-idle-change-delay . 1.0))
  :bind
  ((flycheck-mode-map
    ("M-n" . flycheck-next-error)
    ("M-p" . flycheck-previous-error))))

(leaf flycheck-eglot
  :after (flycheck eglot)
  :custom
  ((flycheck-eglot-exclusive . nil))
  :global-minor-mode global-flycheck-eglot-mode)

(leaf org
  :tag "builtin"
  :custom
  ((org-src-preserve-indentation . nil)
   (org-edit-src-content-indentation . 0)
   (org-use-speed-commands . t)
   (org-directory . "~/org")
   (org-agenda-files . '("~/org/todo.org" "~/org/schedule.org"))
   (org-agenda-span . 'day)
   (org-log-done . 'time))
  :bind
  (("<f2>" . hydra-org/body)
   (org-mode-map
    ("M-SPC" . hydra-org-mode/body)))
  :hydra
  ((hydra-org
    (:hint nil :exit t)
    "
^Command^
^^------------
_a_: agenda
_c_: capture
"
    ("a" org-agenda)
    ("c" org-capture)
    ("C-m" nil)
    ("q" nil))
   (hydra-org-mode
    (:hint nil)
    "
^Next^             ^Previous^         ^Functions^
^^^^^^-----------------------------------------
_h_: heading       _H_: heading       _t_: timer
_l_: link          _L_: link
_b_: block         _B_: block
_f_: field(table)  _F_: field(table)
_r_: row(table)
"
    ("h" org-next-visible-heading)
    ("l" org-next-link)
    ("b" org-next-block)
    ("f" org-table-next-field)
    ("r" org-table-next-row)
    ("H" org-previous-visible-heading)
    ("L" org-previous-link)
    ("B" org-previous-block)
    ("F" org-table-previous-field)
    ("t" hydra-org-timer/body :exit t)
    ("C-m" nil :exit t)
    ("q" nil :exit t))
   (hydra-org-timer
    (:hint nil :exit t)
    "
^Command^
^^--------------------
_b_: start
_B_: set timer
_e_: stop
_p_: pause
_i_: insert
_I_: insert as item
"
    ("b" org-timer-start)
    ("B" org-timer-set-timer)
    ("e" org-timer-stop)
    ("p" org-timer-pause-or-continue)
    ("i" org-timer)
    ("I" org-timer-item)
    ("C-m" nil)
    ("q" nil)))
  :config
  (leaf org-capture
    :tag "builtin"
    :custom
    (org-capture-templates
     . '(("t" "Todo" entry (file "~/org/todo.org")
          "* TODO %?\n")
         ("s" "Schedule" entry (file "~/org/schedule.org")
          "* %?\n")))))

(leaf csv-mode
  :hook
  ((csv-mode-hook . csv-align-mode)))

(leaf bash-ts-mode
  :tag "builtin"
  :mode "\\.sh\\'" "\\.bash\\'")

(leaf dockerfile-ts-mode
  :tag "builtin"
  :mode "Dockerfile\\'")

(leaf go-ts-mode
  :tag "builtin"
  :mode "\\.go\\'")

(leaf go-mod-ts-mode
  :tag "builtin"
  :mode "go\\.mod\\'")

(leaf java-ts-mode
  :tag "builtin"
  :mode "\\.java\\'")

(leaf json-ts-mode
  :tag "builtin"
  :mode "\\.json\\'")

(leaf lua-ts-mode
  :tag "builtin"
  :mode "\\.lua\\'")

(leaf markdown-ts-mode
  :tag "builtin"
  :mode "\\.md\\'" "\\.markdown\\'")

(leaf nix-ts-mode
  :mode "\\.nix\\'")

(leaf python-ts-mode
  :tag "builtin"
  :mode "\\.py\\'")

(leaf terraform-mode
  :mode "\\.tf\\'" "\\.tfvars\\'")

(leaf hcl-mode
  :mode "\\.hcl\\'")

(leaf toml-ts-mode
  :tag "builtin"
  :mode "\\.toml\\'")

(leaf yaml-ts-mode
  :tag "builtin"
  :mode "\\.ya?ml\\'")

(leaf cc-mode
  :tag "builtin"
  :custom
  ((c-default-style . "gnu")
   (c-basic-offset . 4)))

(leaf compile
  :tag "builtin"
  :custom
  ((compilation-read-command . nil)
   (compilation-scroll-output . 'first-error)))

(leaf project
  :tag "builtin"
  :custom
  ((project-vc-extra-root-markers
    . '("bb.edn"
        "bun.lock"
        "bun.lockb"
        "build.gradle"
        "build.gradle.kts"
        "Cargo.toml"
        "compose.yaml"
        "deno.json"
        "deno.jsonc"
        "deps.edn"
        "devenv.nix"
        "docker-compose.yml"
        "compose.yml"
        "docker-compose.yaml"
        "flake.nix"
        "go.mod"
        "go.work"
        "gradlew"
        "jsconfig.json"
        "justfile"
        "Justfile"
        ".luarc.json"
        ".luarc.jsonc"
        "main.tf"
        "Makefile"
        "mise.toml"
        "mvnw"
        "package-lock.json"
        "package.json"
        "Package.swift"
        "Pipfile"
        "pnpm-lock.yaml"
        "pnpm-workspace.yaml"
        "poetry.lock"
        "pom.xml"
        "project.clj"
        "pyproject.toml"
        "requirements.txt"
        "settings.gradle"
        "settings.gradle.kts"
        "setup.cfg"
        "setup.py"
        "shadow-cljs.edn"
        "shell.nix"
        "stylua.toml"
        "Taskfile.yml"
        "Taskfile.yaml"
        "terraform.tf"
        "tsconfig.json"
        "uv.lock"
        "versions.tf"
        "yarn.lock"))))

(leaf direnv
  :require t
  :config
  (direnv-mode 1))

(leaf docker
  :custom
  ((docker-compose-command . "docker compose")
   (docker-container-shell-file-name . "/bin/bash")
   (docker-show-status . t))
  :bind
  (("C-c d" . docker)))

(leaf ace-window
  :custom
  ((aw-keys . '(?a ?s ?d ?f ?g ?h ?j ?k ?l))
   (aw-background . nil))
  :bind
  (("M-o" . ace-window)))

(leaf apheleia
  :require t
  :global-minor-mode apheleia-global-mode
  :config
  (setf (alist-get 'goimports apheleia-formatters) '("goimports"))
  (setf (alist-get 'go-ts-mode apheleia-mode-alist) 'goimports)

  (setf (alist-get 'ruff apheleia-formatters) '("ruff" "format" "--stdin-filename" filepath "-"))
  (setf (alist-get 'python-ts-mode apheleia-mode-alist) 'ruff)

  (setf (alist-get 'nixfmt apheleia-formatters) '("nixfmt"))
  (setf (alist-get 'nix-ts-mode apheleia-mode-alist) 'nixfmt)

  (setf (alist-get 'shfmt apheleia-formatters) '("shfmt" "-i" "2" "-"))
  (setf (alist-get 'bash-ts-mode apheleia-mode-alist) 'shfmt)

  (setf (alist-get 'stylua apheleia-formatters) '("stylua" "--search-parent-directories" "-"))
  (setf (alist-get 'lua-ts-mode apheleia-mode-alist) 'stylua)

  (setf (alist-get 'google-java-format apheleia-formatters) '("google-java-format" "--aosp" "-"))
  (setf (alist-get 'java-ts-mode apheleia-mode-alist) 'google-java-format)

  (setf (alist-get 'prettier apheleia-formatters) '("prettier" "--stdin-filepath" filepath))
  (dolist (mode '(json-ts-mode yaml-ts-mode markdown-ts-mode))
    (setf (alist-get mode apheleia-mode-alist) 'prettier))

  (setf (alist-get 'taplo apheleia-formatters) '("taplo" "fmt" "-"))
  (setf (alist-get 'toml-ts-mode apheleia-mode-alist) 'taplo))

(leaf exec-path-from-shell
  :when (eq system-type 'darwin)
  :require t
  :config
  (exec-path-from-shell-initialize))

(leaf doom-modeline
  :global-minor-mode doom-modeline-mode
  :custom
  ((doom-modeline-icon . nil)
   (doom-modeline-major-mode-icon . nil)
   (doom-modeline-buffer-file-name-style . 'truncate-upto-project)
   (doom-modeline-battery . t)
   (doom-modeline-time . t)))

(leaf catppuccin-theme
  :require t
  :custom
  ((catppuccin-flavor . 'latte))
  :config
  (load-theme 'catppuccin :no-confirm))

;; One ordinary Emacs process owns the standard server.  Keep this after the
;; rest of startup so batch evaluation never creates a socket and the ADE
;; package is loaded only after its platform edge has been initialized.
(ade-platform-start-standard-server)
(require 'ade)

(provide 'init)

;;; init.el ends here
