;;; ade-platform.el --- Platform-specific ADE/Emacs integration -*- lexical-binding: t; -*-

;;; Commentary:

;; Keep host-specific behaviour at the edge of ADE.  The core registry and
;; adapters do not need to know whether this Emacs is running on macOS,
;; native Linux, or WSL.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function skk-mode "skk" (&optional arg))
(declare-function skk-latin-mode "skk" (arg))
(declare-function skk-j-mode-on "skk-macs" (&optional katakana))
(declare-function set-fontset-font "fontset" (fontset charset font
                                                 &optional frame add))
(declare-function server-running-p "server" ())
(defvar skk-user-directory)

(defgroup ade-platform nil
  "Platform-specific integration for ADE."
  :group 'ade)

(defconst ade-platform-latin-font "DejaVuSansM Nerd Font Mono"
  "Font family used for Latin text and the default face.")

(defconst ade-platform-cjk-font "Noto Sans Mono CJK JP"
  "Font family used for Japanese and other CJK text.")

(defconst ade-platform-symbol-font "Noto Sans Mono"
  "Font family used for symbols and the Unicode fallback.")

(defconst ade-platform--wsl-marker-variables
  '("WSL_DISTRO_NAME" "WSL_INTEROP")
  "Environment markers that positively identify a WSL process.")

(defconst ade-platform--terminal-modes
  '(term-mode eat-mode vterm-mode comint-mode)
  "Major modes in which automatic SKK activation is forbidden.")

(defvar ade-platform--initialized-p nil
  "Non-nil after platform hooks have been installed.")

(defun ade-platform--non-empty-environment-variable-p (name)
  "Return non-nil when environment variable NAME is a non-empty marker."
  (let ((value (getenv name)))
    (and (stringp value)
         (not (string-empty-p value)))))

(defun ade-platform--wsl-marker-p ()
  "Return non-nil when a WSL environment marker is present.

This helper intentionally does not inspect the kernel.  `ade-platform-wsl-p'
uses it first and only falls back to the kernel marker when no environment
marker is available."
  (cl-some #'ade-platform--non-empty-environment-variable-p
           ade-platform--wsl-marker-variables))

(defun ade-platform--kernel-wsl-p ()
  "Return non-nil when Linux reports a Microsoft/WSL kernel marker."
  (and (eq system-type 'gnu/linux)
       (file-readable-p "/proc/sys/kernel/osrelease")
       (with-temp-buffer
         (insert-file-contents-literally "/proc/sys/kernel/osrelease")
         (goto-char (point-min))
         (let ((case-fold-search t))
           (re-search-forward "\\(?:microsoft\\|wsl\\)" nil t)))))

(defun ade-platform-wsl-p ()
  "Return non-nil only for Linux running under WSL.

The positive environment markers are authoritative when present.  Kernel
inspection is a fallback for launches that do not preserve those markers;
the predicate never uses hostname, `wsl.exe', or a `/mnt/c' heuristic."
  (and (eq system-type 'gnu/linux)
       (if (ade-platform--wsl-marker-p)
           t
         (ade-platform--kernel-wsl-p))))

(defun ade-platform-terminal-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is a terminal or terminal-like buffer."
  (with-current-buffer (or buffer (current-buffer))
    (apply #'derived-mode-p ade-platform--terminal-modes)))

(defun ade-platform-editing-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is an ordinary editable buffer.

Minibuffers and terminal buffers are deliberately excluded.  Fundamental
mode is accepted for file-less scratch/edit buffers; prompt buffers still
require the explicit prompt helper below."
  (with-current-buffer (or buffer (current-buffer))
    (and (not (minibufferp (current-buffer)))
         (not (ade-platform-terminal-buffer-p (current-buffer)))
         (or (derived-mode-p 'text-mode 'prog-mode)
             (eq major-mode 'fundamental-mode)))))

(defun ade-platform--start-skk-latin ()
  "Enable buffer-local SKK and leave its input submode in Latin mode."
  (require 'skk)
  (unless (bound-and-true-p skk-mode)
    (skk-mode 1))
  (skk-latin-mode 1)
  ;; ddskk normally installs this binding itself.  Keep the contract local
  ;; to our Latin map so C-j remains an explicit transition to Hiragana even
  ;; when a user customisation changes the package defaults.
  (when (boundp 'skk-latin-mode-map)
    (define-key skk-latin-mode-map (kbd "C-j") #'skk-j-mode-on))
  t)

(defun ade-platform--enable-skk-in-editing-buffer ()
  "Turn on SKK in the current ordinary editing buffer on WSL."
  (when (and (ade-platform-wsl-p)
             (ade-platform-editing-buffer-p))
    (ade-platform--start-skk-latin)))

(defun ade-platform-enable-prompt-skk (&optional hiragana)
  "Explicitly enable SKK in a prompt buffer.

Automatic activation excludes terminal and prompt buffers.  A prompt owner
may call this helper after selecting the prompt; with HIRAGANA non-nil the
helper starts directly in Hiragana, otherwise it follows the normal Latin
start and C-j transition contract."
  (interactive "P")
  (unless (ade-platform-wsl-p)
    (user-error "Prompt SKK is enabled only on WSL"))
  (ade-platform--start-skk-latin)
  (when hiragana
    (skk-j-mode-on))
  t)

(defalias 'ade-platform-enable-skk-for-prompt #'ade-platform-enable-prompt-skk)

(defun ade-platform--configure-ddskk ()
  "Load ddskk's WSL-only configuration and install its hooks."
  (setq skk-user-directory (expand-file-name ".ddskk/" "~"))
  ;; Loading here makes `.ddskk/init' available to ddskk's first invocation,
  ;; while the actual minor mode remains buffer-local.
  (require 'skk)
  (add-hook 'text-mode-hook #'ade-platform--enable-skk-in-editing-buffer)
  (add-hook 'prog-mode-hook #'ade-platform--enable-skk-in-editing-buffer)
  t)

(defun ade-platform-rescale-factor (reference-advance target-advance
                                     &optional target-columns)
  "Return a scale for TARGET-ADVANCE relative to REFERENCE-ADVANCE.

TARGET-COLUMNS defaults to one.  A two-column CJK glyph therefore uses two
times the reference advance before dividing by its measured target advance.
Invalid or zero measurements return one, leaving Emacs' normal font fallback
untouched."
  (if (and (numberp reference-advance)
           (> reference-advance 0)
           (numberp target-advance)
           (> target-advance 0))
      (/ (* (float (or target-columns 1)) reference-advance)
         target-advance)
    1.0))

(defun ade-platform--font-advance (family character frame)
  "Measure CHARACTER's advance in font FAMILY on FRAME.

The measurement uses the actual opened font glyph metrics rather than a
fixed height or a universal scale constant.  Return nil when the font is not
available on the selected display."
  (when (and (display-graphic-p frame)
             (fboundp 'find-font)
             (fboundp 'open-font)
             (fboundp 'font-get-glyphs))
    (condition-case nil
        (let* ((entity (find-font (font-spec :family family) frame))
               (font (and entity (open-font entity frame))))
          (when font
            (unwind-protect
                (with-temp-buffer
                  (let* ((glyphs (font-get-glyphs font 0 (length character)
                                                   character))
                         (glyph (and glyphs (aref glyphs 0))))
                    (and glyph (aref glyph 4))))
              (close-font font))))
      (error nil))))

(defun ade-platform--set-font-rescale (font factor)
  "Set FONT's measured rescale FACTOR in the global font rescale alist."
  (when (and (stringp font) (numberp factor) (> factor 0))
    (setq face-font-rescale-alist
          (cons (cons (regexp-quote font) factor)
                (cl-remove-if
                 (lambda (entry)
                   (equal (car entry) (regexp-quote font)))
                 face-font-rescale-alist)))))

(defun ade-platform--set-fontset-font (charset family frame)
  "Map CHARSET to FAMILY on FRAME."
  (set-fontset-font t charset (font-spec :family family) frame))

(defun ade-platform-apply-fonts (&optional frame)
  "Apply ADE's GUI font mapping and measured per-font rescaling to FRAME.

No face height is set here: the user's normal/default Emacs height remains
unchanged."
  (setq frame (or frame (selected-frame)))
  (when (display-graphic-p frame)
    (set-face-attribute 'default frame :family ade-platform-latin-font)
    (ade-platform--set-fontset-font 'unicode ade-platform-symbol-font frame)
    (ade-platform--set-fontset-font 'latin ade-platform-latin-font frame)
    (dolist (charset '(han kana cjk-misc bopomofo))
      (ade-platform--set-fontset-font charset ade-platform-cjk-font frame))
    (let ((latin-advance
           (ade-platform--font-advance ade-platform-latin-font "M" frame))
          (cjk-advance
           (ade-platform--font-advance ade-platform-cjk-font "あ" frame))
          (symbol-advance
           (ade-platform--font-advance ade-platform-symbol-font "★" frame)))
      (when (and latin-advance cjk-advance)
        (ade-platform--set-font-rescale
         ade-platform-cjk-font
         (ade-platform-rescale-factor latin-advance cjk-advance 2)))
      (when (and latin-advance symbol-advance)
        (ade-platform--set-font-rescale
         ade-platform-symbol-font
         (ade-platform-rescale-factor latin-advance symbol-advance)))))
  frame)

(defun ade-platform-start-standard-server ()
  "Start Emacs' standard server for an interactive normal process.

Batch and daemon processes are intentionally left alone so they never create
or contend for a client socket during package checks or other noninteractive
invocations."
  (when (and (not noninteractive)
             (not (and (fboundp 'daemonp) (daemonp))))
    (require 'server)
    (unless (server-running-p)
      (server-start))))

(defun ade-platform-initialize ()
  "Install platform hooks and apply settings for the current session."
  (unless ade-platform--initialized-p
    (setq ade-platform--initialized-p t)
    (add-hook 'after-make-frame-functions #'ade-platform-apply-fonts)
    (when (ade-platform-wsl-p)
      (ade-platform--configure-ddskk)))
  (when (display-graphic-p)
    (ade-platform-apply-fonts))
  t)

(provide 'ade-platform)

;;; ade-platform.el ends here
