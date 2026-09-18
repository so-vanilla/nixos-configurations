;;; ade-ui-test.el --- Standalone ERT for ADE Prompt/sidebar/public entry -*- lexical-binding: t; -*-

;;; Commentary:

;; Run from the repository root with:
;;
;;   emacs --batch -Q -L .emacs.d/lisp/ade -L test \
;;     -l test/ade-ui-test.el -f ert-run-tests-batch-and-exit
;;
;; App Server, Ghostel, Perspective, and window display calls are stubbed.  The
;; tests focus on ownership, send guards, rendering, and explicit attach
;; boundaries rather than live GUI or network behaviour.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'button)
(require 'ade)

(defvar ade-ui-test--ghostel-defined nil)

(unless (fboundp 'ghostel-mode)
  (define-derived-mode ghostel-mode fundamental-mode "Ghostel"
    "Test-only Ghostel major mode marker."))

(defmacro ade-ui-test-with-clean-state (&rest body)
  "Run BODY with isolated ADE registry and UI state."
  `(unwind-protect
       (progn
         (ade-core-reset)
         (setq ade-prompt--buffers (make-hash-table :test #'equal)
               ade-sidebar--buffer nil
               ade-sidebar--window nil)
         ,@body)
     (dolist (buffer (buffer-list))
       (when (and (buffer-live-p buffer)
                  (with-current-buffer buffer
                    (and (boundp 'ade-prompt-owner-uuid)
                         ade-prompt-owner-uuid)))
         (kill-buffer buffer)))
     (ade-core-reset)
     (setq ade-prompt--buffers (make-hash-table :test #'equal)
           ade-sidebar--buffer nil
           ade-sidebar--window nil)))

(defun ade-ui-test-workspace (uuid name &optional root worktree)
  "Return a fixture Workspace."
  (ade-workspace-create :uuid uuid
                        :name name
                        :root (or root "/tmp")
                        :worktree worktree
                        :perspective-name uuid
                        :prompt-buffer nil
                        :agent-ids nil
                        :selected-agent-id nil
                        :metadata nil))

(defun ade-ui-test-agent (id workspace-uuid thread-id &optional state origin)
  "Return a fixture Agent with STATE and ORIGIN."
  (ade-agent-create :id id
                    :workspace-uuid workspace-uuid
                    :thread-id thread-id
                    :session-id (format "session-%s" id)
                    :main-thread-id thread-id
                    :state (or state 'idle)
                    :turn-origin (or origin 'ade)
                    :pending-requests nil))

(defun ade-ui-test-register (&optional state origin)
  "Register one Workspace and Agent fixture and return both."
  (let ((workspace (ade-core-register-workspace
                    (ade-ui-test-workspace "uuid-a" "alpha" "/tmp"
                                            "/tmp/worktree")))
        (agent (ade-ui-test-agent "agent-a" "uuid-a" "thread-a"
                                  state origin)))
    (ade-core-register-agent agent)
    (list workspace agent)))

;;; Prompt ownership and send controls

(ert-deftest ade-ui-prompt-is-one-fileless-buffer-per-workspace ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register))
          (workspace (car records))
          (first (ade-prompt-for-workspace workspace))
          (second (ade-prompt-for-workspace "alpha")))
     (should (eq first second))
     (with-current-buffer first
       (should (ade-prompt-buffer-p))
       (should (equal ade-prompt-owner-uuid "uuid-a"))
       (should-not buffer-file-name)
       (should (derived-mode-p 'org-mode)))
     (should (= 1 (hash-table-count ade-prompt--buffers))))))

(ert-deftest ade-ui-prompt-keymap-has-normal-and-side-send-bindings ()
  (ade-ui-test-with-clean-state
   (ade-ui-test-register)
   (with-current-buffer (ade-prompt-for-workspace "alpha")
     (should (eq (key-binding (kbd "C-c '") nil) #'ade-prompt-send))
     (should (eq (key-binding (kbd "C-c \"") nil) #'ade-prompt-send-side)))))

(ert-deftest ade-ui-prompt-normal-send-clears-only-on-acceptance ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register))
          (agent (cadr records))
          (prompt (ade-prompt-for-workspace "alpha"))
          (calls nil))
     (with-current-buffer prompt
       (insert "normal payload")
       (cl-letf (((symbol-function 'ade-send-turn)
                  (lambda (sent-agent text callback &rest options)
                    (setq calls (list sent-agent text options))
                    (funcall callback
                             sent-agent
                             (ade-send-snapshot--make
                              :agent-id (ade-agent-id sent-agent)
                              :thread-id (ade-agent-thread-id sent-agent)
                              :turn-id "turn-a"
                              :client-user-message-id "client-a"
                              :generation 1)
                             'accepted))))
         (ade-prompt-send nil)))
     (should (eq (car calls) agent))
     (should (equal (cadr calls) "normal payload"))
     (should-not (caddr calls))
     (with-current-buffer prompt
       (should (equal (buffer-string) ""))))))

(ert-deftest ade-ui-prompt-failed-send-retains-body ()
  (ade-ui-test-with-clean-state
   (ade-ui-test-register)
   (let ((prompt (ade-prompt-for-workspace "alpha")))
     (with-current-buffer prompt
       (insert "retain me")
       (cl-letf (((symbol-function 'ade-send-turn)
                  (lambda (&rest _args) (error "injected send failure"))))
         (ade-prompt-send nil))
       (should (equal (buffer-string) "retain me"))
       (should ade-prompt-warning)))))

(ert-deftest ade-ui-prompt-async-send-error-retains-body-and-warns ()
  (ade-ui-test-with-clean-state
   (ade-ui-test-register)
   (let ((prompt (ade-prompt-for-workspace "alpha")))
     (with-current-buffer prompt
       (insert "async retain me")
       (cl-letf (((symbol-function 'ade-send-turn)
                  (lambda (agent _text callback &rest _options)
                    (funcall callback agent nil '(error "server unavailable")))))
         (ade-prompt-send nil))
       (should (equal (buffer-string) "async retain me"))
       (should (string-match-p "server unavailable"
                               (or ade-prompt-warning "")))))))

(ert-deftest ade-ui-prompt-mismatch-selected-nil-and-prefixes-never-send ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register))
          (workspace (car records))
          (agent (cadr records))
          (calls nil)
          (prompt (ade-prompt-for-workspace workspace)))
     (with-current-buffer prompt
       (insert "guarded")
       (cl-letf (((symbol-function 'ade-send-turn)
                  (lambda (&rest _args) (setq calls (1+ (or calls 0)))))
                 ((symbol-function 'ade-send-steer)
                  (lambda (&rest _args) (setq calls (1+ (or calls 0)))))
                 ((symbol-function 'ade-send-interrupt)
                  (lambda (&rest _args) (setq calls (1+ (or calls 0)))))
                 ((symbol-function 'ade-prompt--confirm-takeover)
                  (lambda (_agent) nil))
                 ((symbol-function 'ade-prompt--consult-agent)
                  (lambda (&rest _args) nil)))
         ;; Mismatch is viewable but non-destructive.
         (let ((other (ade-core-register-workspace
                       (ade-ui-test-workspace "uuid-b" "beta"))))
           (ignore other)
           (ade-core-set-current "uuid-b")
           (ade-prompt-send nil))
         ;; Restore owner and clear selection; still no send.
         (ade-core-set-current "uuid-a")
         (ade-core-clear-selected-agent "uuid-a")
         (ade-prompt-send nil)
         ;; Numeric/repeated prefixes are no-send.  C-u consult cancellation
         ;; is covered by the dedicated consult test below.
         (ade-prompt-send 3)
         (ade-prompt-send '(16)))
       (should (= (or calls 0) 0))
       (should (equal (buffer-string) "guarded"))
       (should ade-prompt-warning)))))

(ert-deftest ade-ui-prompt-universal-prefix-consults-agent-then-dispatches ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register 'working 'ade))
          (agent (cadr records))
          (prompt (ade-prompt-for-workspace "alpha"))
          (consulted nil)
          (call nil))
     (ade-agent-set-current-turn-id agent "turn-a")
     (ade-core-clear-selected-agent "uuid-a")
     (with-current-buffer prompt
       (insert "consult steer payload")
       (let ((ade-prompt-agent-consult-function
              (lambda (candidates)
                (setq consulted candidates)
                agent)))
         (cl-letf (((symbol-function 'ade-send-steer)
                    (lambda (sent-agent text expected &optional _callback)
                      (setq call (list sent-agent text expected)))))
           (ade-prompt-send '(4))))
     (should (equal consulted (list agent)))
     (should (eq (car call) agent))
     (should (equal (cadr call) "consult steer payload"))
     (should (equal (caddr call) "turn-a"))))))

(ert-deftest ade-ui-prompt-unknown-idle-requires-explicit-takeover ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register 'idle 'unknown))
          (agent (cadr records))
          (prompt (ade-prompt-for-workspace "alpha"))
          (calls nil)
          (confirm nil))
     (with-current-buffer prompt
       (insert "takeover payload")
       (cl-letf (((symbol-function 'ade-prompt--confirm-takeover)
                  (lambda (_agent) confirm))
                 ((symbol-function 'ade-send-turn)
                  (lambda (sent-agent text callback &rest options)
                    (setq calls (list sent-agent text options))
                    (funcall callback sent-agent
                             (ade-send-snapshot--make
                              :agent-id (ade-agent-id sent-agent)
                              :thread-id (ade-agent-thread-id sent-agent)
                              :turn-id "turn-a"
                              :client-user-message-id "client-a"
                              :generation 1)
                             'accepted))))
         (ade-prompt-send nil)
         (should-not calls)
         (setq confirm t)
         (ade-prompt-send nil)))
     (should (eq (car calls) agent))
     (should (equal (cadr calls) "takeover payload"))
     (should (equal (caddr calls) '(:takeover t))))))

(ert-deftest ade-ui-prompt-consult-cancel-keeps-selection-and-body ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register 'working 'ade))
          (workspace (car records))
          (agent (cadr records))
          (prompt (ade-prompt-for-workspace "alpha"))
          (called nil))
     (with-current-buffer prompt
       (insert "cancelled consult")
       (let ((ade-prompt-agent-consult-function
              (lambda (&rest _args) (signal 'quit nil))))
         (cl-letf (((symbol-function 'ade-send-turn)
                    (lambda (&rest _args) (setq called t)))
                   ((symbol-function 'ade-send-steer)
                    (lambda (&rest _args) (setq called t))))
           (ade-prompt-send '(4))))
       (should-not called)
       (should (equal (ade-workspace-selected-agent-id workspace)
                      (ade-agent-id agent)))
       (should (equal (buffer-string) "cancelled consult"))))))

(ert-deftest ade-ui-prompt-side-send-requires-known-side-and-clears-on-acceptance ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register))
          (agent (cadr records))
          (prompt (ade-prompt-for-workspace "alpha"))
          (calls nil)
          (known t))
     (with-current-buffer prompt
       (insert "side payload")
       (cl-letf (((symbol-function 'ade-side-known-p)
                  (lambda (&rest _args) known))
                 ((symbol-function 'ade-side-send)
                  (lambda (sent-agent text callback &optional _errorback)
                    (setq calls (list sent-agent text))
                    (funcall callback 'side 'accepted))))
         (ade-prompt-send-side nil))
       (should (equal calls (list agent "side payload")))
       (should (equal (buffer-string) ""))
       (insert "unknown side")
       (setq known nil calls nil)
       (ade-prompt-send-side nil)
       (should-not calls)
       (should (equal (buffer-string) "unknown side"))))))

(ert-deftest ade-ui-prompt-active-or-blocked-unknown-is-no-send ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register 'working 'unknown))
          (agent (cadr records))
          (prompt (ade-prompt-for-workspace "alpha"))
          (called nil))
     (with-current-buffer prompt
       (insert "do not send")
       (cl-letf (((symbol-function 'ade-send-turn)
                  (lambda (&rest _args) (setq called t))))
         (ade-prompt-send nil)))
     (should-not called)
     (should (equal (with-current-buffer prompt (buffer-string))
                    "do not send")))))

(ert-deftest ade-ui-prompt-explicit-skk-helper-is-not-automatic ()
  (ade-ui-test-with-clean-state
   (ade-ui-test-register)
   (let ((called nil))
     (cl-letf (((symbol-function 'ade-platform-enable-prompt-skk)
                (lambda (&optional hiragana)
                  (setq called hiragana)
                  t)))
       (let ((prompt (ade-prompt-for-workspace "alpha")))
         (with-current-buffer prompt
           (should-not called)
           (ade-prompt-enable-skk t)
           (should called)))))))

;;; Sidebar controls and render boundary

(ert-deftest ade-ui-sidebar-renders-human-fields-and-hides-uuids ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register 'working 'ade))
          (agent (cadr records))
          (buffer (progn
                    (setq ade-sidebar--buffer
                          (get-buffer-create ade-sidebar-buffer-name))
                    (with-current-buffer ade-sidebar--buffer
                      (ade-sidebar-mode))
                    ade-sidebar--buffer)))
     (setf (ade-agent-unread-p agent) t)
     (with-current-buffer buffer
       (ade-sidebar-refresh)
       (should (string-match-p "alpha" (buffer-string)))
       (should (string-match-p "root:/tmp" (buffer-string)))
       (should (string-match-p "worktree:/tmp/worktree" (buffer-string)))
       (should (string-match-p "agents:1" (buffer-string)))
       (should (string-match-p "agent-a" (buffer-string)))
       (should (string-match-p "state:working" (buffer-string)))
       (should (string-match-p "unread" (buffer-string)))
       (should-not (string-match-p "uuid-a" (buffer-string)))))))

(ert-deftest ade-ui-sidebar-buttons-switch-workspace-and-select-agent-only ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register))
          (agent (cadr records))
          (buffer (progn
                    (setq ade-sidebar--buffer
                          (get-buffer-create ade-sidebar-buffer-name))
                    (with-current-buffer ade-sidebar--buffer
                      (ade-sidebar-mode))
                    ade-sidebar--buffer))
          (switches nil)
          (selections nil))
     (with-current-buffer buffer
       (ade-sidebar-refresh)
       (let ((workspace-button (progn
                                 (goto-char (point-min))
                                 (search-forward "alpha")
                                 (button-at (1- (point)))))
             (agent-button (progn
                             (goto-char (point-min))
                             (search-forward "agent-a")
                             (button-at (1- (point))))))
         (cl-letf (((symbol-function 'ade-workspace-switch)
                    (lambda (uuid) (setq switches (cons uuid switches))))
                   ((symbol-function 'ade-core-select-agent)
                    (lambda (uuid agent-id)
                      (setq selections (list uuid agent-id))))
                   ((symbol-function 'ade-sidebar-refresh)
                    (lambda (&optional _buffer) t)))
           (button-activate workspace-button)
           (button-activate agent-button)))
     (should (equal switches '("uuid-a" "uuid-a")))
     (should (equal selections '("uuid-a" "agent-a")))
     (should (eq (ade-core-agent-by-id "agent-a") agent))))))

(ert-deftest ade-ui-sidebar-keyboard-move-reorders-without-perspective-switch ()
  (ade-ui-test-with-clean-state
   (ade-ui-test-register)
   (ade-core-register-workspace (ade-ui-test-workspace "uuid-b" "beta"))
   (let ((calls 0))
     (cl-letf (((symbol-function 'ade-workspace-switch)
                (lambda (&rest _args) (setq calls (1+ calls)))))
       (ade-sidebar-move-workspace 1))
     (should (= calls 0))
     (should (equal (mapcar #'ade-workspace-name (ade-core-workspaces))
                    '("beta" "alpha"))))))

(ert-deftest ade-ui-sidebar-state-hook-refreshes-only-open-sidebar ()
  (ade-ui-test-with-clean-state
   (ade-ui-test-register)
   (setq ade-sidebar--buffer (get-buffer-create ade-sidebar-buffer-name))
   (let ((refreshes 0))
     (cl-letf (((symbol-function 'ade-sidebar--window)
                (lambda () t))
               ((symbol-function 'ade-sidebar-refresh)
                (lambda (&optional _buffer) (setq refreshes (1+ refreshes)))))
       (ade-sidebar--state-change nil nil))
     (should (= refreshes 1)))))

;;; Public entry and explicit Ghostel attach

(ert-deftest ade-ui-ade-require-is-inert-and-init-displays-only-prompt ()
  (ade-ui-test-with-clean-state
   (let ((calls nil))
     (cl-letf (((symbol-function 'ade-workspace-init)
                (lambda () (setq calls (append calls '(workspace)))
                  'workspace))
               ((symbol-function 'ade-prompt-display-current)
                (lambda () (setq calls (append calls '(prompt)))
                  'prompt))
               ((symbol-function 'ade--install-explicit-attach-hook)
                (lambda () (setq calls (append calls '(attach-hook)))))
               ((symbol-function 'ade-sidebar-toggle)
                (lambda () (setq calls (append calls '(sidebar)))))
               ((symbol-function 'ade-sidebar-open)
                (lambda () (setq calls (append calls '(sidebar-open))))))
       (should (eq (ade-init) 'workspace)))
     (should (equal calls '(workspace attach-hook prompt)))
     (should-not (memq 'sidebar calls)))))

(ert-deftest ade-ui-explicit-c-x-b-ghostel-attach-selects-known-agent ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register))
          (workspace (car records))
          (agent (cadr records)))
     (ade-core-clear-selected-agent "uuid-a")
     (with-temp-buffer
       (ghostel-mode)
       (set (make-local-variable 'ade-ghostel-agent-id) "agent-a")
       (setf (ade-agent-buffer agent) (current-buffer))
       (should (eq (ade-attach-current-buffer) agent))
       (should (equal (ade-workspace-selected-agent-id workspace)
                      "agent-a"))))))

(ert-deftest ade-ui-ghostel-without-protocol-identity-is-not-attached ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register))
          (workspace (car records))
          (agent (cadr records)))
     (ade-core-clear-selected-agent (ade-workspace-uuid workspace))
   (with-temp-buffer
     (ghostel-mode)
     (should-not (ade-attach-current-buffer))
     (should-not (ade-agent-buffer agent))
     (should-not (ade-workspace-selected-agent-id workspace))))))

(ert-deftest ade-ui-non-ghostel-c-x-b-does-not-attach ()
  (ade-ui-test-with-clean-state
   (ade-ui-test-register)
   (with-temp-buffer
     (fundamental-mode)
     (should-error (ade-attach-current-buffer) :type 'user-error)
     (should-not (ade-agent-buffer (ade-core-agent-by-id "agent-a"))))))

(ert-deftest ade-ui-post-command-hook-gates-attach-to-switch-to-buffer ()
  (ade-ui-test-with-clean-state
   (let* ((records (ade-ui-test-register))
          (workspace (car records))
          (agent (cadr records))
          (calls 0))
     (ade-core-clear-selected-agent "uuid-a")
     (with-temp-buffer
       (ghostel-mode)
       (set (make-local-variable 'ade-ghostel-agent-id) "agent-a")
       (setf (ade-agent-buffer agent) (current-buffer))
       (cl-letf (((symbol-function 'ade-attach-current-buffer)
                  (lambda () (setq calls (1+ calls)))))
         (let ((this-command 'find-file))
           (ade--maybe-attach-after-switch-to-buffer))
         (should (= calls 0))
         (let ((this-command 'switch-to-buffer))
           (ade--maybe-attach-after-switch-to-buffer))
         (should (= calls 1)))
       (should-not (ade-workspace-selected-agent-id workspace))))))

(provide 'ade-ui-test)

;;; ade-ui-test.el ends here
