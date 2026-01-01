;;; init.el --- My init.el -*- lexical-binding: t; -*-

;;; Author: Shuto Omura <somura-vanilla@so-icecream.com>

;;; Commentary:

;;; Code:
(setq lsp-client 'lsp-mode)

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
     (tab-width . 4)
     (gc-cons-threshold . 10000000)
     (read-process-output-max . 1048576)))

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
     (backup-inhibited . nil)
     (major-mode-remap-alist . '((yaml-mode . yaml-ts-mode)))))

  (leaf simple
    :tag "builtin"
    :preface
    (defun clipboard-copy (text)
      (setq copy-process (make-process :name "clipboard-copy"
					                   :buffer nil
					                   :command '("wl-copy" "-n")
					                   :connection-type 'pipe
					                   :noquery t))
      (process-send-string copy-process text)
      (process-send-eof copy-process))
    (defun clipboard-paste ()
      (if (and copy-process (process-live-p copy-process))
	      nil
	    (shell-command-to-string "wl-paste -n | tr -d \\r")))
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
     (indent-tabs-mode . nil))
    :config
    (setq interprogram-cut-function 'clipboard-copy)
    (setq interprogram-paste-function 'clipboard-paste)
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
    :global-minor-mode t)

  (leaf subr
    :tag "builtin"
    :config
    (keyboard-translate ?\C-h ?\C-?))

  (leaf autorevert
    :tag "builtin"
    :global-minor-mode global-auto-revert-mode)

  (leaf delsel
    :tag "builtin"
    :global-minor-mode delete-selection-mode)

  (leaf window
    :tag "builtin"
    :custom
    (split-width-threshold . nil))

  (leaf eag-config
    :tag "builtin"
    :custom
    (epa-pinentry-mode . 'loopback))

  (leaf kmacro
    :tag "builtin"
    :preface
    (defun my-kmacro-call-macro ()
      "Call the last keyboard macro."
      (interactive)
      (kmacro-end-and-call-macro 1)
      (hydra-kmacro/body))
    :bind
    (("C-x e" . my-kmacro-call-macro))
    :hydra
    ((hydra-kmacro
      (:hint nil)
      "
^Repeat^
^^--------------
  _e_: call
_C-g_: splice
"
      ("e" kmacro-call-macro)
      ("C-g" nil :exit t)
      ("C-m" nil :exit t)
      ("q" nil :exit t)))))

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
     ("M-/" . avy-goto-end-of-line)
     ("M-?" . avy-goto-line))))


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
    :url "https://github.com/magit/magit"
    :config
    (leaf forge
      :after magit)))

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
     ("C-M-s" . consult-ripgrep)
     (minibuffer-mode-map
      ("C-r" . consult-history))))

  (leaf embark-consult
    :url "https://github.com/oantolin/embark"
    :bind
    ((global-map
      :package emacs
      ("M-." . embark-dwin)
      ("C-." . embark-act)))
    :hook
    (embark-collect-mode . consult-preview-at-point-mode)))

(leaf *completion
  :init
  (defgroup lsp-client-settings nil
    "LSPクライアント設定."
    :group 'programming)

  (defcustom my-default-lsp-client 'lsp-mode
    "デフォルトのLSPクライアントを選択します."
    :type '(choice (const :tag "lsp-mode" lsp-mode)
                   (const :tag "Eglot" eglot))
    :group 'lsp-client-settings)

  (defcustom my-enabled-lsp-servers
    '()
    "有効なLSPサーバのリスト."
    :type '(repeat string)
    :group 'lsp-client-settings)

  :custom
  (((my-default-lsp-client . 'lsp-mode)))
    
  :config
  (leaf eglot
    :tag "builtin"
    :if (eq my-default-lsp-client 'eglot)
    :hook
    ((c-mode-hook . eglot-ensure)
     (clojure-mode-hook . eglot-ensure)
     (css-mode-hook . eglot-ensure)
     (dockerfile-mode . eglot-ensure)
     (go-mode-hook . eglot-ensure)
     (latex-mode-hook . eglot-ensure)
     (lua-mode-hook . eglot-ensure)
     (markdown-mode-hook . eglot-ensure)
     (mhtml-mode-hook . eglot-ensure)
     (java-mode-hook . eglot-ensure)
     (js-mode-hook . eglot-ensure)
     (nix-mode-hook . eglot-ensure)
     (python-mode-hook . eglot-ensure)
     (rust-mode-hook . eglot-ensure)
     (yaml-ts-mode-hook . eglot-ensure)))

  (leaf lsp-mode
    :url "https://github.com/emacs-lsp/lsp-mode"
    :if (eq my-default-lsp-client 'lsp-mode)
    :hook
    ((c-mode-hook . lsp)
     (clojure-mode-hook . lsp)
     (css-mode-hook . lsp)
     (dockerfile-mode . lsp)
     (go-mode-hook . lsp)
     (latex-mode-hook . lsp)
     (lua-mode-hook . lsp)
     (markdown-mode-hook . lsp)
     (mhtml-mode-hook . lsp)
     (java-mode-hook . lsp)
     (js-mode-hook . lsp)
     (nix-mode-hook . lsp)
     (python-mode-hook . lsp)
     (rust-mode-hook . lsp)
     (terraform-mode-hook . lsp)
     (yaml-ts-mode-hook . lsp)
     (yaml-ts-mode-hook . lsp)
     (lsp-mode . lsp-enable-which-key-integration)
     (lsp-mode-hook . lsp-lens-mode))
    :custom
    ((lsp-keymap-prefix . "M-l")
     (lsp-disabled-clients . '(tfls))
     (lsp-terraform-ls-enable-show-reference . t)
     (lsp-terraform-ls-prefill-required-fields . t))
    :config
    (lsp-register-client
     (make-lsp-client :new-connection (lsp-stdio-connection '("nixd"))
                      :major-modes '(nix-mode)
                      :priority 0
                      :server-id 'nixd))
    
    (leaf lsp-pyright
      :url "https://github.com/emacs-lsp/lsp-pyright"
      :hook
      ((python-mode-hook . (lambda ()
                             (require 'lsp-pyright)
                             (lsp)))))

    (leaf lsp-java
      :url "https://github.com/emacs-lsp/lsp-java"
      :hook
      ((java-mode-hook . (lambda ()
                             (require 'lsp-java)
                             (lsp))))
      :config
      (leaf lsp-java-boot
        :url "https://github.com/emacs-lsp/lsp-java"
        :hook
        ((java-mode-hook . lsp-java-boot-lens-mode))))

    (leaf lsp-ui
      :url "https://github.com/emacs-lsp/lsp-ui"
      :global-minor-mode lsp-ui-mode
      :custom
      ((lsp-ui-sideline-show-hover . t)))))

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
    (corfu-history-mode)
    (corfu-popupinfo-mode)
    
    (leaf corfu-terminal
      :url "https://codeberg.org/akib/emacs-corfu-terminal"
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

(leaf *coding-assistant
  (leaf flycheck
    :url "https://github.com/flycheck/flycheck"
    :global-minor-mode global-flycheck-mode
    :bind
    (flycheck-mode-map
     ("M-n" . flycheck-next-error)
     ("M-p" . flycheck-previous-error))))

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
    :config
    (defun org-journal-kosu--parse-journal-file (path)
      "Parse org journal file at PATH and return parsed buffer."
      (with-temp-buffer
        (insert-file-contents path)
        (org-mode)
        (org-element-parse-buffer)))

    (defun org-journal-kosu--get-headings (parsed)
      "Extract all headings from PARSED org buffer."
      (let ((headings '()))
        (progn
          (org-element-map parsed 'headline
            (lambda (hl)
              (push hl headings)))
          headings)))

    (defun org-journal-kosu--is-start-with-time (title)
      "Check if TITLE starts with time format HH:MM."
      (string-match "^\\([0-9]\\{2\\}:[0-9]\\{2\\}\\) \\(.*\\)$" title))

    (defun org-journal-kosu--to-time-and-tag-list (headings)
      "Convert HEADINGS to list of time and tag entries."
      (mapcar (lambda (hl)
                (let ((raw-title (org-element-property :raw-value hl))
                      (tags (org-element-property :tags hl)))
                  (if (org-journal-kosu--is-start-with-time raw-title)
                      (let ((time-str (match-string 1 raw-title))
                            (work-desc (match-string 2 raw-title)))
                        (list :time time-str :tags tags)))))
              headings))

    (defun org-journal-kosu--time-to-duration (time-tag-list)
      "Convert TIME-TAG-LIST to duration entries between consecutive tasks."
      (let* ((filtered-list (seq-filter 'identity time-tag-list))
             (sorted-list (sort filtered-list
                                (lambda (a b)
                                  (string< (plist-get a :time) (plist-get b :time)))))
             (result '()))
        (dotimes (i (1- (length sorted-list)))
          (let* ((current (nth i sorted-list))
                 (next (nth (1+ i) sorted-list))
                 (current-time (plist-get current :time))
                 (next-time (plist-get next :time))
                 (current-tags (plist-get current :tags))
                 (next-tags (plist-get next :tags))
                 (current-minutes (+ (* (string-to-number (substring current-time 0 2)) 60)
                                     (string-to-number (substring current-time 3 5))))
                 (next-minutes (+ (* (string-to-number (substring next-time 0 2)) 60)
                                  (string-to-number (substring next-time 3 5))))
                 (duration (cond
                            ;; If current task is before 12:00 and next is 12:00 or after, end at 12:00
                            ((and (< current-minutes 720) (>= next-minutes 720))
                             (- 720 current-minutes))
                            ;; Normal case
                            (t (- next-minutes current-minutes)))))
            (when (and current-tags (> (length current-tags) 0))
              (push (list :duration duration :tags current-tags) result))))
        (reverse result)))

    (defun org-journal-kosu--sum-durations-by-tag (duration-tag-list)
      "Sum durations in DURATION-TAG-LIST grouped by tags."
      (let ((result '()))
        (dolist (entry duration-tag-list)
          (when entry
            (let ((duration (plist-get entry :duration))
                  (tags (plist-get entry :tags)))
              (dolist (tag tags)
                (let ((existing (assoc tag result)))
                  (if existing
                      (setcdr existing (+ (cdr existing) duration))
                    (push (cons tag duration) result)))))))
        result))

    (defun org-journal-kosu--format-result (tag-duration-alist)
      "Format TAG-DURATION-ALIST into readable string with HH:MM format."
      (mapconcat (lambda (item)
                   (let ((minutes (cdr item))
                         (hours (/ (cdr item) 60))
                         (mins (% (cdr item) 60)))
                     (format "%s: %02d:%02d" (car item) hours mins)))
                 tag-duration-alist "\n"))

    (defun org-journal-kosu--write-to-temp-buffer (formatted-string)
      "Write FORMATTED-STRING to temporary buffer and display it."
      (with-current-buffer (get-buffer-create "*Journal Analysis*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "Journal Time Analysis\n")
          (insert "=====================\n\n")
          (insert formatted-string)
          (goto-char (point-min))
          (read-only-mode 1)
          (display-buffer (current-buffer)))))

    (defun org-journal-kosu-by-journal-file (file-path)
      "Analyze journal file at FILE-PATH and display time analysis."
      (->> file-path
           org-journal-kosu--parse-journal-file
           org-journal-kosu--get-headings
           org-journal-kosu--to-time-and-tag-list
           org-journal-kosu--time-to-duration
           org-journal-kosu--sum-durations-by-tag
           org-journal-kosu--format-result
           org-journal-kosu--write-to-temp-buffer))

    (defun org-journal-kosu-yesterday ()
      "Analyze yesterday's journal file and display time analysis."
      (interactive)
      (let ((yesterday-file (format-time-string "~/org/journal/%Y-%m-%d.org"
                                                (time-subtract (current-time) (days-to-time 1)))))
        (org-journal-kosu-by-journal-file yesterday-file)))

    (defun org-journal-kosu-by-date ()
      "Analyze journal file from date and display time analysis."
      (interactive)
      (let* ((date-string (read-string "Enter date (YYYY-MM-DD): "))
             (journal-file (format "~/org/journal/%s.org" date-string)))
        (org-journal-kosu-by-journal-file journal-file)))
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
      (org-ai-default-chat-model . "gpt-4o")))

  (leaf org-gfm
    :url "https://github.com/larstvei/ox-gfm"
    :after org)

  (leaf org-pomodoro
    :url "https://github.com/marcinkoziej/org-pomodoro")

  (leaf org-download
    :url "https://github.com/abo-abo/org-download"
    :hook
    ((org-mode-hook . org-download-enable))
    :custom
    ((org-download-method . 'directory)
     (org-download-image-dir . "~/org/images")))

  (leaf valign
    :url "https://github.com/casouri/valign"
    :hook
    ((org-mode-hook . valign-mode)))

  (leaf org-present
    :url "https://github.com/rlister/org-present"
    :hook
    ((org-present-mode-hook
      . (lambda ()
          (org-present-big)
          (org-display-inline-images)
          (org-present-hide-cursor)
          (org-present-read-only)))
     (org-present-mode-quit-hook
      . (lambda ()
          (org-present-small)
          (org-remove-inline-images)
          (org-present-show-cursor)
          (org-present-read-write)))))

  (leaf org-superstar
    :url "https://github.com/integral-dw/org-superstar-mode"
    :hook
    ((org-mode-hook . org-superstar-mode))))

(leaf *language
  :config
  (leaf cc-mode
    :tag "builtin"
    :custom
    ((c-default-style . "gnu")
     (c-basic-offset . 4)))

  (leaf clojure-mode
    :url "https://github.com/clojure-emacs/clojure-mode"
    :config
    (leaf cider
      :url "https://github.com/clojure-emacs/cider"
      :bind
      ((cider-repl-mode-map
        ("M-RET" . cider-repl-newline-and-indent))))

    (leaf clj-deps-new
      :url "https://github.com/jpe90/emacs-clj-deps-new"))

  (leaf dockerfile-mode
    :url "https://github.com/spotify/dockerfile-mode")

  (leaf elisp-mode
    :tag "builtin")

  (leaf go-mode
    :url "https://github.com/dominikh/go-mode.el"
    :hook
    ((before-save-hook . gofmt-before-save))
    :custom
    ((gofmt-command . "goimports")))

  (leaf lua-mode
    :url "https://github.com/immerrr/lua-mode")

  (leaf mhtml-mode
    :tag "builtin"
    :mode "\\.svelte\\'")

  (leaf nix-mode
    :url "https://github.com/NixOS/nix-mode")

  (leaf python-mode
    :url "https://gitlab.com/python-mode-devs/python-mode/")

  (leaf rustic
    :url "https://github.com/emacs-rustic/rustic"
    :custom
    ((rustic-format-on-save . t)
     (rustic-cargo-use-last-stored-auguments . t)
     (rustic-lsp-client my-default-lsp-client))
    :config
    (leaf cargo
      :url "https://github.com/kwrooijen/cargo.el"))

  (leaf terraform-mode
    :url "https://github.com/hcl-emacs/terraform-mode"
    :custom
    ((terraform-indent-level . 2)
     (hcl-indent-level . 2)))

  (leaf tex-mode
    :tag "builtin")

  (leaf tsx-ts-mode
    :tag "builtin"
    :mode "\\.tsx\\'")

  (leaf typescript-ts-mode
    :tag "builtin"
    :mode "\\.ts\\'")

  (leaf yaml-ts-mode
    :tag "builtin"
    :mode "\\.yaml\\'"))

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
    :url "https://github.com/chep/copilot-chat.el")
  
  (if (file-exists-p "~/repos/github.com/manzaltu/claude-code-ide.el/")
      (progn
        (add-to-list 'load-path "~/repos/github.com/manzaltu/claude-code-ide.el")
        (leaf claude-code-ide
          :ensure nil
          :custom
          ((claude-code-ide-terminal-backend . 'eat))
          :bind (("C-x c m" . claude-code-ide-menu)
                 ("C-x c t" . claude-code-ide-toggle))))))

(leaf *others
  :config
  (leaf projectile
    :global-minor-mode t
    :bind
    (("C-x C-p" . projectile-command-map)))

  (leaf direnv
    :url "https://github.com/wbolster/emacs-direnv"
    :global-minor-mode t)

  (leaf mistty
    :url "https://github.com/szermatt/mistty")

  (leaf eat
    :url "https://codeberg.org/akib/emacs-eat"
    :hook
    ((eshell-first-time-mode-hook . eat-eshell-visual-command-mode)
     (eat-mode-hook . corfu-mode))
    :custom
    ((eat-enable-auto-line-mode . t))
    :init
    (defun eat-toggle-mode ()
      "Toggle eat-mode."
      (interactive)
      (if eat--semi-char-mode
          (eat-emacs-mode)
        (eat-semi-char-mode)))
    :config
    (customize-set-variable
     'eat-semi-char-non-bound-keys
     (append
      (list (vector meta-prefix-char ?e) (vector meta-prefix-char ?o))
      eat-semi-char-non-bound-keys))
    :bind
    (eat-mode-map
     ("M-e" . eat-toggle-mode)))
  
  (leaf jinx
    :url "https://github.com/minad/jinx"
    :global-minor-mode global-jinx-mode
    :custom
    ((jinx-languages . "en_US")
     (jinx-exclude-regexps . '((emacs-lisp-mode "Package-Requires:.*$")
                               (t
                                "[ぁ-んァ-ヶ一-龠ー]+[a-zA-Z]+"
                                "[a-zA-Z]+[ぁ-んァ-ヶ一-龠ー]+"
                                "[ぁ-んァ-ヶ一-龠ー]+"
                                "[A-Z]+\\>" "-+\\>"
                                "\\w*?[0-9]\\w*\\>"
                                "[a-z]+://\\S-+"
                                "<?[-+_.~a-zA-Z][-+_.~:a-zA-Z0-9]*@[-.a-zA-Z0-9]+>?"
                                "\\(?:Local Variables\\|End\\):\\s-*$"
                                "jinx-\\(?:languages\\|local-words\\):\\s-+.*$"))))
    :bind
    (("M-$" . jinx-correct)
     ("C-M-$" . jinx-languages)))

  (leaf dirvish
    :url "https://github.com/alexluigit/dirvish"
    :init
    (dirvish-override-dired-mode)
    :bind
    (("C-x d" . dirvish)))

  (leaf ace-window
    :url "https://github.com/abo-abo/ace-window"
    :custom
    ((aw-keys . '(?a ?s ?d ?f ?g ?h ?j ?k ?l))
     (aw-background . nil))
    :bind
    (("M-o" . ace-window)))

  (leaf ddskk
    :url "https://github.com/skk-dev/ddskk"
    :if (not is-private-host)
    :custom
    ((skk-preload . t)
     (skk-user-directory . "~/.ddskk")
     (skk-init-file . "~/.ddskk/init")
     (skk-large-jisyo . "~/.ddskk/SKK-JISYO.L"))
    :bind
    (("C-x C-j" . skk-mode))))

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
    (load-theme 'catppuccin :no-confirm)
    (set-cursor-color (catppuccin-get-color 'pink)))

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
    :global-minor-mode t
    :custom
    ((nyan-wavy-trail . t)
     (nyan-animate-nyancat . t)
     (nyan-bar-length . 16)
     (nyan-minimub-window-width . 80)))

  (leaf parrot
    :url "https://github.com/dp12/parrot"
    :global-minor-mode t
    :custom
    ((parrot-num-rotations . nil))))

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

;;; init.el ends here
