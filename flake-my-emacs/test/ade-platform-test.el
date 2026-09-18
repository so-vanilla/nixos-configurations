;;; ade-platform-test.el --- Tests for ADE platform integration -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((root (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../.emacs.d/lisp/ade" root)))
(require 'ade-platform)

(ert-deftest ade-platform-wsl-marker-is-authoritative ()
  "A positive WSL environment marker must avoid kernel probing."
  (let ((system-type 'gnu/linux))
    (cl-letf (((symbol-function 'getenv)
               (lambda (name)
                 (when (equal name "WSL_DISTRO_NAME")
                   "Ubuntu")))
              ((symbol-function 'ade-platform--kernel-wsl-p)
               (lambda ()
                 (ert-fail "kernel fallback was reached despite a marker"))))
      (should (ade-platform-wsl-p)))))

(ert-deftest ade-platform-wsl-kernel-is-fallback ()
  "The kernel marker is consulted when environment markers are absent."
  (let ((system-type 'gnu/linux))
    (cl-letf (((symbol-function 'getenv) (lambda (_name) nil))
              ((symbol-function 'ade-platform--kernel-wsl-p) (lambda () t)))
      (should (ade-platform-wsl-p)))))

(ert-deftest ade-platform-wsl-is-linux-only ()
  "WSL markers on non-Linux hosts must not enable WSL behaviour."
  (let ((system-type 'darwin))
    (cl-letf (((symbol-function 'getenv) (lambda (_name) "Ubuntu"))
              ((symbol-function 'ade-platform--kernel-wsl-p)
               (lambda () (ert-fail "non-Linux host reached kernel fallback"))))
      (should-not (ade-platform-wsl-p)))))

(ert-deftest ade-platform-terminal-buffers-are-excluded ()
  "Terminal-like major modes are not ordinary SKK editing buffers."
  (with-temp-buffer
    (setq major-mode 'term-mode)
    (should (ade-platform-terminal-buffer-p))
    (should-not (ade-platform-editing-buffer-p))))

(ert-deftest ade-platform-fundamental-buffer-is-editable ()
  "A normal file-less fundamental-mode buffer can opt into SKK."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (should-not (ade-platform-terminal-buffer-p))
    (should (ade-platform-editing-buffer-p))))

(ert-deftest ade-platform-rescale-factor-uses-measurements ()
  "Rescaling is derived from measured advances and target column width."
  (should (= 2.0 (ade-platform-rescale-factor 10 10 2)))
  (should (= 1.0 (ade-platform-rescale-factor 0 10)))
  (should (= 1.0 (ade-platform-rescale-factor 10 0))))

(ert-deftest ade-platform-rescale-alist-replaces-font-entry ()
  "A recalculated font factor does not accumulate stale duplicate entries."
  (let ((face-font-rescale-alist nil))
    (ade-platform--set-font-rescale "Noto Sans Mono" 1.25)
    (ade-platform--set-font-rescale "Noto Sans Mono" 1.5)
    (should (= 1.5 (cdr (assoc "Noto Sans Mono" face-font-rescale-alist))))
    (should (= 1 (length face-font-rescale-alist)))))

(ert-deftest ade-platform-batch-does-not-start-server ()
  "Batch evaluation must not load or start the standard server."
  (let ((noninteractive t)
        (called nil))
    (cl-letf (((symbol-function 'require)
               (lambda (&rest _args) (setq called t))))
      (ade-platform-start-standard-server)
      (should-not called))))

(ert-deftest ade-platform-prompt-skk-is-explicit-opt-in ()
  "Prompt SKK is enabled only when its explicit helper is called."
  (let ((started nil)
        (entered-hiragana nil))
    (cl-letf (((symbol-function 'ade-platform-wsl-p) (lambda () t))
              ((symbol-function 'ade-platform--start-skk-latin)
               (lambda () (setq started t)))
              ((symbol-function 'skk-j-mode-on)
               (lambda (&optional _katakana) (setq entered-hiragana t))))
      (should (ade-platform-enable-prompt-skk t))
      (should started)
      (should entered-hiragana))))

;;; ade-platform-test.el ends here
