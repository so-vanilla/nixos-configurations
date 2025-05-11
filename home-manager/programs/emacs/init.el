;;; init.el --- My init.el

;; Author: Shuto Omura <somura-vanilla@so-icecream.com>

;; Commentary:

;;; Code:

(let ((private-hosts '("vanilla"))
      (current-host (system-name)))
  (defvar is-private-host
    (if (member current-host private-hosts)
        t
      nil)))

(use-package leaf)

(leaf *leaf
  :config
  (leaf leaf-keywords
    :config
    (leaf-keywords-init))

  (leaf leaf-convert)

  (leaf leaf-tree
    :custom
    ((imenu-list-size . 30)
     (imenu-list-position . 'left)))

  (leaf hydra))

(leaf *emacs-settings
  :config
  (leaf emacs
    :tag "builtin"
    :hook
    ((prog-mode-hook . (lambda ()
                         (setq-local show-trailing-whitespace t))))
    :custom
    ((frame-title-format . '("%b"))
     (ring-bell-function . 'ignore)
     (use-file-dialog . nil)
     (use-short-answers . t)
     (create-lockfiles . nil)
     (tab-width . 4)))

  (leaf startup
    :tag "builtin"
    :custom
    ((inhibit-splash-screen . t)
     (inhibit-startup-screen . t)
     (inhibit-startup-buffer-menu . t)))

  (leaf scroll-bar
    :tag "builtin"
    :config
    (scroll-bar-mode -1))

  (leaf menu-bar
    :tag "builtin"
    :config
    (menu-bar-mode -1))

  (leaf tool-bar
    :tag "builtin"
    :config
    (tool-bar-mode -1))

  (leaf files
    :tag "builtin"
    :custom
    ((make-backup-files . nil)
     (backup-inhibited . nil)))

  (leaf simple
    :tag "builtin"
    :preface
    (defun clipboard-copy (text)
      (setq copy-process (make-process :name "clipboard-copy"
					                   :buffer nil
					                   :command (if is-private-host
                                                    '("wl-copy" "-n")
                                                  '("clip.exe"))
					                   :connection-type 'pipe
					                   :noquery t))
      (process-send-string copy-process text)
      (process-send-eof copy-process))
    (defun clipboard-paste ()
      (if (and copy-process (process-live-p copy-process))
	      nil
	    (if is-private-host
            (shell-command-to-string "wl-paste -n | tr -d \\r")
          (shell-command-to-string "powershell.exe -command Get-Clipboard | tr -d \\r"))))
    (defun my-move-beginning-of-line ()
      "Move point to first non-whitespace character or beginning-of-line."
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
    ((before-save-hook . (delete-trailing-whitespace)))
    :custom
    ((copy-process . nil)
     (interprogram-cut-function . 'clipboard-copy)
     (interprogram-paste-function . 'clipboard-paste)
     (indent-tabs-mode . nil))
    :bind
    (("C-x u" . my-undo)
     ("C-x r" . my-redo)
     ("C-a" . my-move-beginning-of-line))
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

  (leaf faces
    :tag "builtin"
    :config
    (set-face-attribute 'default nil
                        :family "DejaVuSansM Nerd Font Mono"
		                :height 100
		                :weight 'normal
		                :width 'normal))

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
    :global-minor-mode t))

(leaf *cursor
  :config
  (leaf isearch
    :tag "builtin"
    :custom
    ((isearch-allow-scroll . t)))

  (leaf avy
    :url "https://github.com/abo-abo/avy"
    :bind
    (("C-;" . avy-goto-char-in-line)
     ("C-/" . avy-goto-char-timer)
     ("M-/" . avy-goto-line))))


(leaf *pair
  :config
  (leaf elec-pair
    :tag "builtin"
    :global-minor-mode electric-pair-mode
    :hook
    ((minibuffer-mode-hook . (lambda ()
				               (if (not (eq this-command 'eval-expression))
					               (electric-pair-local-mode 0)
				                 nil)))))

  (leaf paren
    :tag "builtin"
    :global-minor-mode show-paren-mode
    :custom
    (show-paren-style 'mixed))

  (leaf puni
    :url "https://github.com/AmaiKinono/puni"
    :global-minor-mode puni-global-mode
    :bind
    ((puni-mode-map
      ("C-k" . (lambda ()
                 (interactive)
                 (if (derived-mode-p 'prog-mode)
                     (progn
                       (puni-kill-line)
                       (indent-for-tab-command))
                   (puni-kill-line))))
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
                _{_: barf-backward}
"
      ("C-w" puni-squeeze)
      ("s" puni-splice)
      ("]" puni-slurp-forward)
      ("}" puni-barf-forward)
      ("[" puni-slurp-backward)
      ("{" puni-barf-backward)
      ("C-m" nil :exit t)
      ("q" nil :exit t)))))

(leaf *window
  :config
  (leaf windmove
    :tag "builtin"
    :bind
    (("C-x o" . hydra-windmove/body))
    :hydra
    ((hydra-windmove
      (:hint nil)
      "
^Direction^
^^-----------
_C-f_: right
_C-b_: left
_C-p_: up
_C-n_: down
"
      ("C-f" windmove-right)
      ("C-b" windmove-left)
      ("C-p" windmove-up)
      ("C-n" windmove-down)
      ("C-m" nil :exit t)
      ("q" nil :exit t)))))

(leaf *vcs
  :config
  (leaf magit
    :url "https://github.com/magit/magit"))

(leaf *minibuffer
  :config
  (leaf vertico
    :url "https://github.com/minad/vertico"
    :global-minor-mode t)

  (leaf orderless
    :url "https://github.com/oantolin/orderless"
    :custom
    ((completion-styles . '(orderless basic))
     (completion-category-overrides . '((file (style basic partial-completion))))
     (orderless-matching-styles . '(orderless-literal
				                    orderless-prefixes
				                    orderless-initialism
				                    orderless-regexp))))

  (leaf marginalia
    :url "https://github.com/minad/marginalia"
    :global-minor-mode t)

  (leaf consult
    :url "https://github.com/minad/consult"
    :bind
    (([remap switch-to-buffer] . consult-buffer)
     ([remap imenu] . consult-imenu)
     ([remap goto-line] . consult-goto-line)
     ("C-s". consult-line)
     (minibuffer-mode-map
      ("C-r" . consult-history))))

  (leaf embark-consult
    :url "https://github.com/oantolin/embark"
    :bind
    ((minibuffer-mode-map
      ("M-." . embark-dwin)
      ("C-." . embark-act)))))

(leaf eglot
  :tag "builtin"
  :hook
  ((c-mode-hook . eglot-ensure)
   (clojure-mode-hook . eglot-ensure)
   (css-mode-hook . eglot-ensure)
   (go-mode-hook . eglot-ensure)
   (lua-mode-hook . eglot-ensure)
   (markdown-mode-hook . eglot-ensure)
   (mhtml-mode-hook . eglot-ensure)
   (java-mode-hook . eglot-ensure)
   (js-mode-hook . eglot-ensure)
   (nix-mode-hook . eglot-ensure)
   (python-mode-hook . eglot-ensure)
   (rust-mode-hook . eglot-ensure)
   (latex-mode-hook . eglot-ensure)))

(leaf *inline-completion
  :config
  (leaf corfu
    :url "https://github.com/minad/corfu"
    :global-minor-mode global-corfu-mode
    :init
    (eval-after-load 'corfu
    '(setq corfu-mode-map nil))
    :custom
    ((corfu-auto . t)
     (corfu-auto-delay . 0)
     (corfu-auto-prefix . 1))
    :bind
    ((corfu-map
      ("C-g" . corfu-quit)
      ("C-i" . corfu-complete)
      ("C-n" . corfu-next)
      ("C-p" . corfu-previous)
      ("<tab>" . nil)
      ("RET" . nil)
      ("<down>" . nil)
      ("<up>" . nil)
      ("C-M-i" . nil)
      ("M-SPC" . nil)
      ("M-g" . nil)
      ("M-h" . nil)
      ("M-n" . nil)
      ("M-p" . nil)
      ("[remap beginning-of-buffer]" . nil)
      ("[remap completion-at-point]" . nil)
      ("[remap end-of-buffer]" . nil)
      ("[remap keyboard-escape-quit]" . nil)
      ("[remap move-beginning-of-line]" . nil)
      ("[remap move-end-of-line]" . nil)
      ("[remap next-line]" . nil)
      ("[remap previous-line]" . nil)
      ("[remap scroll-down-command]" . nil)
      ("[remap scroll-up-command]" . nil)))
    :config
    (leaf corfu-terminal
      :url "https://codeberg.org/akib/emacs-corfu-terminal"
      :if (not is-private-host)
      :doc "Temporary solution. Corfu support for terminal Emacs31. After release, remove this."))

  (leaf cape
    :url "https://github.com/minad/cape"
    :config
    (add-to-list 'completion-at-point-functions #'cape-dabbrev)
    (add-to-list 'completion-at-point-functions #'cape-file)
    (add-to-list 'completion-at-point-functions #'cape-elisp-block)
    (add-to-list 'completion-at-point-functions #'cape-elisp-symbol))

  (leaf tempel
    :url "https://github.com/minad/tempel"
    :global-minor-mode global-tempel-abbrev-mode
    :hook
    ((prog-mode-hook . tempel-setup-capf)
     (text-mode-hook . tempel-setup-capf)
     (conf-mode-hook . tempel-setup-capf))
    :custom
    ((tempel-trigger-prefix . ";"))
    :init
    (defun tempel-setup-capf ()
      (setq-local completion-at-point-functions
                  (cons #'tempel-complete completion-at-point-functions)))
    :bind
    ((tempel-map
      ("M-<down>" . nil)
      ("M-<up>" . nil)
      ("M-{" . nil)
      ("M-}" . nil)
      ("C-]" . tempel-next)
      ("C-[" . tempel-previous)))
    :config
    (leaf tempel-collection
      :url "https://github.com/Crandel/tempel-collection")))

(leaf *programming-assistant
  :config
  (leaf flymake
    :tag "builtin"
    :bind
    (("M-n" . flymake-goto-next-error)
     ("M-p" . flymake-goto-prev-error))))

(leaf org
  :tag "builtin"
  :custom
  ((org-src-preserve-indentation . nil)
   (org-edit-src-content-indentation . 0)
   (org-use-speed-commands . t)
   (org-directory . "~/org"))
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
_j_: journal
_r_: roam
_c_: capture
_s_: sync CalDAV
"
    ("a" org-agenda)
    ("j" hydra-org-journal/body)
    ("r" hydra-org-roam/body)
    ("s" org-caldav-sync)
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
    ("q" nil :exit t)))
  :config
  (leaf org-agenda
    :tag "builtin"
    :custom
    ((org-agenda-files . '("~/org/todo.org" "~/org/schedule.org"))
     (org-agenda-span . 'day)
     (org-agenda-skip-deadline-if-done . nil)
     (org-agenda-skip-schedule-if-done . nil)
     (org-agenda-skip-deadline-prewarning-if-scheduled . nil)))

  (leaf org-super-agenda
    :url "https://github.com/alphapapa/org-super-agenda"
    :global-minor-mode t
    :custom
    ((org-super-agenda-groups .
      '((:name "Schedule"
               :file-path "~/org/schedule.org"
               :time-grid t)
        (:name "Work"
               :tag "work")
        (:name "Project"
               :tag "project")
        (:name "Search"
               :file-path "~/org/todo.org")
        (:name "Emacs"
               :tag "emacs")
        (:name "Linux"
               :tag "linux")))))

  (leaf org-capture
    :tag "builtin"
    :custom
    (org-capture-templates .
     '(("t" "Todo" entry (file "~/org/todo.org")
        "* TODO %?\n")
       ("s" "Schedule" entry (file "~/org/schedule.org")
        "* %?\n"))))

  (leaf org-timer
    :tag "builtin"
    :hydra
    ((hydra-org-timer
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
      ("q" nil))))

  (leaf org-journal
    :url "https://github.com/bastibe/org-journal"
    :custom
    ((org-journal-dir . "~/org/journal/")
     (org-journal-file-format . "%Y-%m-%d.org"))
    :hydra
    ((hydra-org-journal
      (:hint nil :exit t)
      "
^Open^          ^Search^
^^^^-----------------------------------
_t_: today      _s_: search(calendar)
_n_: new entry  _S_: search(all)
^ ^             _y_: calendar year
^ ^             _m_: calendar month
^ ^             _w_: calendar week
"
      ("t" org-journal-open-current-journal-file)
      ("n" org-journal-new-entry)
      ("s" org-journal-search)
      ("S" org-journal-search-forever)
      ("y" org-journal-search-calendar-year)
      ("m" org-journal-search-calendar-month)
      ("w" org-journal-search-calendar-week)
      ("C-m" nil)
      ("q" nil))))

  (leaf org-roam
    :url "https://github.com/org-roam/org-roam"
    :custom
    `((org-roam-directory . ,(file-truename "~/org/org-roam")))
    :config
    (org-roam-db-autosync-mode)
    :hydra
    ((hydra-org-roam
      (:hint nil :exit t)
      "
^Node^       ^Dailies^                                     ^Other^
^^^^^^--------------------------------------------------------------
_f_: find    _t_: today(goto)     _y_: yesterday(goto)     _s_: sync
_i_: insert  _T_: today(capture)  _Y_: yesterday(capture)  _g_: graph
_r_: random  _d_: date(goto)      _n_: tomorrow(goto)
^ ^          _D_: date(capture)   _N_: tomorrow(capture)
"
      ("f" org-roam-node-find)
      ("i" org-roam-node-insert)
      ("r" org-roam-node-random)
      ("t" org-roam-dailies-goto-today)
      ("T" org-roam-dailies-capture-today)
      ("d" org-roam-dailies-goto-date)
      ("D" org-roam-dailies-capture-date)
      ("y" org-roam-dailies-goto-yesterday)
      ("Y" org-roam-dailies-capture-yesterday)
      ("n" org-roam-dailies-goto-tomorrow)
      ("N" org-roam-dailies-capture-tomorrow)
      ("s" org-roam-db-sync)
      ("g" org-roam-graph)
      ("q" nil))))

  (leaf org-caldav
    :url "https://github.com/dengste/org-caldav"
    :if is-private-host
    :custom
    `((org-caldav-calendars .
                            '((:calendar-id "67B2-67412200-1A7-7F1B4200" :files ("~/org/todo.org")
		                                    :inbox "~/org/todo.org")
                              (:calendar-id "11D3-67412200-21D-48611280" :files ("~/org/schedule.org")
		                                    :inbox "~/org/schedule.org")))
      (org-caldav-url . ,(getenv "CALDAV_LINK"))
      (org-icalendar-timezone . "Asia/Tokyo")
      (org-icalendar-include-todo . 'all)
      (org-caldav-sync-todo . t)))

  (leaf org-ai
    :url "https://github.com/rksm/org-ai"
    :if is-private-host
    :global-minor-mode org-ai-global-mode
    :custom
    `((org-ai-openai-api-token . ,(getenv "ORG_AI_KEY"))
      (org-ai-default-chat-model . "gpt-4o"))))

(leaf *language
  :config
  (leaf cc-mode
    :tag "builtin"
    :custom
    ((c-default-style . "k&r")))

  (leaf clojure-mode
    :url "https://github.com/clojure-emacs/clojure-mode"
    :if is-private-host
    :config
    (leaf cider
      :url "https://github.com/clojure-emacs/cider"
      :if is-private-host
      :bind
      ((cider-repl-mode-map
        ("M-RET" . cider-repl-newline-and-indent))))

    (leaf clj-deps-new
      :url "https://github.com/jpe90/emacs-clj-deps-new"))

  (leaf elisp-mode
    :tag "builtin")

  (leaf go-mode
    :url "https://github.com/dominikh/go-mode.el")

  (leaf lua-mode
    :url "https://github.com/immerrr/lua-mode")

  (leaf nix-mode
    :url "https://github.com/NixOS/nix-mode")

  (leaf python-mode
    :url "https://gitlab.com/python-mode-devs/python-mode/")

  (leaf rustic
    :url "https://github.com/emacs-rustic/rustic"
    :custom
    ((rustic-format-on-save . t)
     (rustic-cargo-use-last-stored-auguments . t)
     (rustic-lsp-client 'eglot))
    :config
    (leaf cargo
      :url "https://github.com/kwrooijen/cargo.el"))

  (leaf tex-mode
    :tag "builtin"))

(leaf *ai-assistant
  :config
  (leaf copilot
    :url "https://github.com/copilot-emacs/copilot.el"
    :hook
    ((prog-mode-hook . copilot-mode))
    :bind
    ((copilot-completion-map
      ("<tab>" . copilot-accept-completion-by-line)
      ("C-<tab>" . copilot-accept-completion-by-word))))

  (leaf copilot-chat
    :url "https://github.com/chep/copilot-chat.el"
    :if is-private-host))

(leaf *others
  :config
  (leaf direnv
    :url "https://github.com/wbolster/emacs-direnv"
    :if is-private-host
    :global-minor-mode t)

  (leaf mistty
    :url "https://github.com/szermatt/mistty"))

(leaf *appearance
  :config
  (leaf doom-modeline
    :url "https://github.com/seagle0128/doom-modeline"
    :global-minor-mode t
    :custom
    ((doom-modeline-battery . t)
     (doom-modeline-time . t))
    :config
    (leaf nerd-icons
      :url "https://github.com/rainstormstudio/nerd-icons.el"))

  (leaf catppuccin-theme
    :url "https://github.com/catppuccin/emacs"
    :custom
    ((catppuccin-flavor . 'latte))
    :config
    (load-theme 'catppuccin :no-confirm))

  (leaf org-modern
    :url "https://github.com/minad/org-modern"
    :global-minor-mode global-org-modern-mode
    :custom
    ((org-auto-align-tags . nil)
     (org-tags-column . 0)
     (org-fold-catch-invisible-edits . 'show-and-error)
     (org-special-ctrl-a/e . t)
     (org-insert-heading-respect-content . t)
     (org-hide-emphasis-markers . t)
     (org-pretty-entities . t)
     (org-ellipsis . "…")
     (org-agenda-tags-column . 0)
     (org-agenda-block-separator . ?─)
     (org-agenda-time-grid . '((daily today require-timed)
                               (800 1000 1200 1400 1600 1800 2000)
                               " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"))
     (org-agenda-current-time-string . "◀── now ─────────────────────────────────────────────────")))

  (leaf nyan-mode
    :url "https://github.com/TeMPOraL/nyan-mode"
    :if is-private-host
    :global-minor-mode t
    :custom
    ((nyan-wavy-trail . t)
     (nyan-animate-nyancat . t)
     (nyan-bar-length . 16)
     (nyan-minimub-window-width . 80)))

  (leaf parrot
    :url "https://github.com/dp12/parrot"
    :if is-private-host
    :global-minor-mode t
    :custom
    ((parrot-num-rotations . nil))))

;; bitwarden
(if is-private-host
    (progn
      (defun bw--unlock (password)
        "This function gets session key from bitwarden cli."
        (if (string= password "")
            (progn
              (message "Password is empty")
              nil)
          (let* ((command (concat "bw unlock " password))
                 (output (shell-command-to-string command)))
            (if (string= output "Invalid master password.")
                (progn
                  (message "Password is invalid")
                  nil)
              (let* ((lines (split-string output "\n"))
                     (target-line (nth 3 lines))
                     (words (split-string target-line "\""))
                     (session-key (nth 1 words)))
                session-key)))))

      (defun bw-unlock ()
        (interactive)
        (if (boundp 'bw-session-key) (message "Bitwarden is already unlocked")
          (let* ((password (read-passwd "Password: "))
                 (session-key (bw--unlock password)))
            (if session-key
                (progn
                  (setq bw-session-key session-key)
                  (message "Bitwarden is unlocked")
                  session-key)
              nil))))

      (defun bw--lock ()
        (let ((command "bw lock"))
          (shell-command-to-string command)))

      (defun bw-lock ()
        (interactive)
        (progn
          (bw--lock)
          (message "Bitwarden is locked")
          (makunbound 'bw-session-key)))

      (defun bw--list-items (session-key)
        "This function return json as a list frombitwarden cli."
        (let* ((command (concat "bw list items --session " session-key))
               (output (shell-command-to-string command)))
          (json-read-from-string output)))

      (defun bw--select-item (handler)
        (if (not (boundp 'bw-session-key))
            (progn
              (message "Bitwarden is not unlocked")
              nil)
          (let* ((items (bw--list-items bw-session-key))
                 (item-names (mapcar (lambda (item) (cdr (assoc 'name item))) items))
                 (item-usernames (mapcar (lambda (item) (cdr (or (assoc 'username (assoc 'login item)) '(name . "")))) items))
                 (item-string (cl-mapcar (lambda (name username) (concat name " :: " username)) item-names item-usernames))
                 (item-alist (cl-mapcar (lambda (key item) (cons key item)) item-string items))
                 (selected (completing-read "Select item: " item-string))
                 (item (cdr (assoc selected item-alist)))
                 (p-or-u (completing-read "Password or Username: " '("password" "username")))
                 (value (cond ((string= p-or-u "password") (cdr (assoc 'password (assoc 'login item))))
                              ((string= p-or-u "username") (cdr (assoc 'username (assoc 'login item)))))))
            (funcall handler value))))

      (defun bw-add-to-kill-ring ()
        (interactive)
        (bw--select-item 'kill-new))

      (defun bw-yank ()
        (interactive)
        (bw--select-item 'insert))

      t)
  nil)

(if is-private-host
    (progn
      (defun playerctl-play ()
        (interactive)
        (shell-command "playerctl play"))

      (defun playerctl-pause ()
        (interactive)
        (shell-command "playerctl pause"))

      (defun playerctl-play-pause ()
        (interactive)
        (shell-command "playerctl play-pause"))

      (defun playerctl-next ()
        (interactive)
        (shell-command "playerctl next"))

      (defun playerctl-previous ()
        (interactive)
        (shell-command "playerctl previous"))

      (defun libpython-init ()
        (interactive)
        (let ((python-home (shell-command-to-string "python -c 'import sys; print(sys.prefix, end=\"\")'")))
          (insert (format "(initialize! :python-home \"%s\")" python-home))))
      t)
  nil)

(provide 'init)
