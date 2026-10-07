;;; ade-core-test.el --- Standalone ERT coverage for ADE core -*- lexical-binding: t; -*-

;;; Commentary:

;; Run from the repository root with:
;;
;;   emacs --batch -Q -L .emacs.d/lisp/ade -L test \
;;     -l test/ade-core-test.el -f ert-run-tests-batch-and-exit
;;
;; Perspective.el is intentionally not required.  The test fixture supplies
;; only the documented calls used by the narrow adapter.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ade-core)
(require 'ade-perspective)
(require 'ade-workspace)
(require 'ade-state)

(defvar persp-mode nil
  "Stubbed Perspective mode variable for standalone ADE tests.")

(defmacro ade-test-with-perspective (&rest body)
  "Evaluate BODY with an isolated in-memory Perspective fixture."
  `(let ((ade-test-perspective-names nil)
         (ade-test-perspective-current nil)
         (ade-test-perspective-calls nil)
         (persp-mode t))
     (cl-labels
         ((record (operation &optional value)
                  (setq ade-test-perspective-calls
                        (append ade-test-perspective-calls
                                (list (list operation value)))))
          (current-name () ade-test-perspective-current)
          (names () (copy-sequence ade-test-perspective-names))
          (switch (name)
                  (record 'switch name)
                  (unless (member name ade-test-perspective-names)
                    (setq ade-test-perspective-names
                          (append ade-test-perspective-names (list name))))
                  (setq ade-test-perspective-current name)
                  name)
          (rename (name)
                  (record 'rename name)
                  (when (member name ade-test-perspective-names)
                    (error "Perspective name already exists: %s" name))
                  (let ((old ade-test-perspective-current))
                    (setq ade-test-perspective-names
                          (cons name (delete old
                                             (copy-sequence
                                              ade-test-perspective-names)))
                          ade-test-perspective-current name)
                    name))
          (kill (&optional name)
                (let ((target (or name ade-test-perspective-current)))
                  (record 'kill target)
                  (unless (member target ade-test-perspective-names)
                    (error "Unknown Perspective: %s" target))
                  (setq ade-test-perspective-names
                        (delete target (copy-sequence
                                        ade-test-perspective-names)))
                  (when (equal target ade-test-perspective-current)
                    (setq ade-test-perspective-current
                          (car ade-test-perspective-names)))
                  t)))
       (cl-letf (((symbol-function 'persp-current-name)
                  (lambda () (current-name)))
                 ((symbol-function 'persp-names)
                  (lambda () (names)))
                 ((symbol-function 'persp-switch)
                  (lambda (name) (switch name)))
                 ((symbol-function 'persp-rename)
                  (lambda (name) (rename name)))
                 ((symbol-function 'persp-kill)
                  (lambda (&optional name) (kill name)))
                 ((symbol-function 'persp-mode)
                  (lambda (&optional _arg) (setq persp-mode t))))
         ,@body))))

(defmacro ade-test-with-clean-core (&rest body)
  "Evaluate BODY with a clean ADE registry and restore it afterwards."
  `(unwind-protect
       (progn
         (ade-core-reset)
         ,@body)
     (ade-core-reset)))

(defun ade-test-workspace (uuid name &optional root)
  "Return a fixture Workspace."
  (ade-workspace-create :uuid uuid
                        :name name
                        :root (or root "/tmp")
                        :worktree nil
                        :perspective-name uuid
                        :prompt-buffer nil
                        :agent-ids nil
                        :selected-agent-id nil
                        :metadata nil))

(defun ade-test-register-workspace (uuid name &optional root)
  "Register and return a fixture Workspace."
  (ade-core-register-workspace (ade-test-workspace uuid name root)))

(defun ade-test-agent (id workspace-uuid thread-id &optional state)
  "Return a fixture Agent."
  (ade-agent-create :id id
                    :workspace-uuid workspace-uuid
                    :thread-id thread-id
                    :session-id (format "session-%s" id)
                    :main-thread-id thread-id
                    :state (or state 'idle)
                    :turn-origin 'ade
                    :pending-requests nil))

;;; Core registry

(ert-deftest ade-core-registers-order-and-current-session-only ()
  (ade-test-with-clean-core
   (let ((first (ade-test-register-workspace "uuid-a" "alpha"))
         (second (ade-test-register-workspace "uuid-b" "beta")))
     (should (equal (mapcar #'ade-workspace-name (ade-core-workspaces))
                    '("alpha" "beta")))
     (should (eq first (ade-core-current-workspace)))
     (should (equal (ade-core-current-uuid) "uuid-a"))
     (should (equal (ade-workspace-uuid
                     (ade-core-workspace-by-name "beta"))
                    "uuid-b"))
     (should (ade-core-validate))
     (should (= (ade-core-workspace-count) 2)))))

(ert-deftest ade-core-rejects-duplicate-name-and-uuid ()
  (ade-test-with-clean-core
   (ade-test-register-workspace "uuid-a" "alpha")
   (should-error (ade-test-register-workspace "uuid-b" "alpha")
                 :type 'ade-name-conflict-error)
   (should-error (ade-test-register-workspace "uuid-a" "beta")
                 :type 'ade-name-conflict-error)
   (should (= (ade-core-workspace-count) 1))
   (should (ade-core-validate))))

(ert-deftest ade-core-rename-replaces-name-without-changing-identity ()
  (ade-test-with-clean-core
   (let* ((workspace (ade-test-register-workspace "uuid-a" "alpha"))
          (agent (ade-test-agent "agent-a" "uuid-a" "thread-a")))
     (ade-core-register-agent agent)
     (should (equal (ade-workspace-selected-agent-id workspace) "agent-a"))
     (ade-core-rename-workspace "uuid-a" "renamed")
     (should-not (ade-core-workspace-by-name "alpha"))
     (should (eq workspace (ade-core-workspace-by-name "renamed")))
     (should (equal (ade-workspace-uuid workspace) "uuid-a"))
     (should (equal (ade-workspace-selected-agent-id workspace) "agent-a"))
     (should-error (ade-core-rename-workspace "uuid-a" "renamed")
                   :type 'ade-name-conflict-error)
     (should (ade-core-validate)))))

(ert-deftest ade-core-selected-agent-obeys-passive-and-explicit-rules ()
  (ade-test-with-clean-core
   (let ((workspace (ade-test-register-workspace "uuid-a" "alpha")))
     (ade-core-register-agent (ade-test-agent "agent-a" "uuid-a" "thread-a"))
     (ade-core-register-agent (ade-test-agent "agent-b" "uuid-a" "thread-b"))
     (should (equal (ade-workspace-selected-agent-id workspace) "agent-a"))
     (ade-core-register-agent (ade-test-agent "agent-c" "uuid-a" "thread-c")
                              t)
     (should (equal (ade-workspace-selected-agent-id workspace) "agent-c"))
     (ade-core-clear-selected-agent "uuid-a" "agent-c")
     (should-not (ade-workspace-selected-agent-id workspace))
     (should-error (ade-core-select-agent "uuid-a" "missing")
                   :type 'ade-invalid-selection-error)
     (should (ade-core-validate)))))

(ert-deftest ade-core-selection-is-workspace-local ()
  (ade-test-with-clean-core
   (let ((first (ade-test-register-workspace "uuid-a" "alpha"))
         (second (ade-test-register-workspace "uuid-b" "beta")))
     (ade-core-register-agent (ade-test-agent "agent-a" "uuid-a" "thread-a"))
     (ade-core-register-agent (ade-test-agent "agent-b" "uuid-b" "thread-b"))
     (ade-core-select-agent "uuid-b" "agent-b")
     (ade-core-set-current "uuid-b")
     (should (equal (ade-workspace-selected-agent-id second) "agent-b"))
     (should (equal (ade-workspace-selected-agent-id first) "agent-a"))
     (ade-core-set-current "uuid-a")
     (should (equal (ade-workspace-selected-agent-id
                     (ade-core-current-workspace))
                    "agent-a")))))

(ert-deftest ade-core-detach-retains-record-and-reattach-is-unselected ()
  (ade-test-with-clean-core
   (let ((workspace (ade-test-register-workspace "uuid-a" "alpha"))
         (agent (ade-test-agent "agent-a" "uuid-a" "thread-a")))
     (ade-core-register-agent agent)
     (ade-core-detach-agent "agent-a")
     (should-not (ade-workspace-agent-ids workspace))
     (should-not (ade-workspace-selected-agent-id workspace))
     (should (ade-core-detached-agent-by-id "agent-a"))
     (ade-core-attach-agent "agent-a" "uuid-a")
     (should (member "agent-a" (ade-workspace-agent-ids workspace)))
     (should-not (ade-workspace-selected-agent-id workspace))
     (ade-core-attach-agent "agent-a" "uuid-a" t)
     (should (equal (ade-workspace-selected-agent-id workspace) "agent-a"))
     (should (ade-core-validate)))))

(ert-deftest ade-core-same-thread-reconnect-updates-existing-agent ()
  (ade-test-with-clean-core
   (ade-test-register-workspace "uuid-a" "alpha")
   (let ((old (ade-test-agent "agent-a" "uuid-a" "thread-a"))
         (new (ade-test-agent "agent-a" "uuid-a" "thread-a" 'working)))
     (ade-core-register-agent old)
     (ade-core-update-agent new)
     (should (eq (ade-core-agent-by-thread "thread-a") new))
     (should (eq (ade-core-agent-by-id "agent-a") new))
     (should (equal (ade-agent-state new) 'working))
     (should (equal (ade-workspace-agent-ids
                     (ade-core-workspace-by-uuid "uuid-a"))
                    '("agent-a"))))))

(ert-deftest ade-core-reorder-clamps-and-adjacent-wraps ()
  (ade-test-with-clean-core
   (ade-test-register-workspace "uuid-a" "alpha")
   (ade-test-register-workspace "uuid-b" "beta")
   (ade-test-register-workspace "uuid-c" "gamma")
   (ade-core-reorder "uuid-c" -10)
   (should (equal (mapcar #'ade-workspace-uuid (ade-core-workspaces))
                  '("uuid-c" "uuid-a" "uuid-b")))
   (ade-core-reorder "uuid-c" 99)
   (should (equal (mapcar #'ade-workspace-uuid (ade-core-workspaces))
                  '("uuid-a" "uuid-b" "uuid-c")))
   (should (equal (ade-core-adjacent-uuid "uuid-c" 1) "uuid-a"))
   (should (equal (ade-core-adjacent-uuid "uuid-a" -1) "uuid-c"))
   (should (ade-core-validate))))

(ert-deftest ade-core-uuid-generator-rejects-duplicates ()
  (ade-test-with-clean-core
   (let ((ade-core-uuid-function (lambda () "generated")))
     (should (equal (ade-core-generate-uuid) "generated"))
     (ade-test-register-workspace "generated" "taken")
     (should-error (ade-core-generate-uuid)
                   :type 'ade-invariant-error))))

;;; Perspective adapter

(ert-deftest ade-perspective-adopt-renames-once-and-preserves-current ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "main")
    (let ((ade-core-uuid-function (lambda () "uuid-adopt")))
      (let ((adoption (ade-perspective-adopt-current)))
        (should (equal (plist-get adoption :old-name) "main"))
        (should (equal (plist-get adoption :uuid) "uuid-adopt"))
        (should (equal (ade-perspective-current-uuid) "uuid-adopt"))
        (should (= (cl-count 'rename ade-test-perspective-calls
                             :key #'car)
                   1)))))))

(ert-deftest ade-perspective-create-and-kill-use-adapter-calls ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-a")
    (ade-perspective-create "uuid-b")
    (should (equal (ade-perspective-current-uuid) "uuid-b"))
    (ade-perspective-kill "uuid-a")
    (should (member "uuid-b" (persp-names)))
    (should-not (member "uuid-a" (persp-names))))))

;;; Workspace lifecycle and transaction boundaries

(ert-deftest ade-workspace-init-is-idempotent ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "main")
    (let ((ade-core-uuid-function (lambda () "uuid-init")))
      (let ((first (ade-workspace-init "/tmp" "editor")))
        (should (equal (ade-workspace-name first) "editor"))
        (should (equal (ade-workspace-uuid first) "uuid-init"))
        (should (= (cl-count 'rename ade-test-perspective-calls :key #'car) 1))
        (let ((second (ade-workspace-init "/tmp" "different")))
          (should (eq first second))
          (should (equal (ade-workspace-name second) "editor"))
          (should (= (cl-count 'rename ade-test-perspective-calls :key #'car)
                     1))))))))

(ert-deftest ade-workspace-create-or-attach-reuses-existing-name ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-a")
    (ade-test-register-workspace "uuid-a" "alpha")
    (let ((attached (ade-workspace-create-or-attach "alpha" "/tmp")))
      (should (equal (ade-workspace-uuid attached) "uuid-a"))
      (should (equal (ade-core-current-uuid) "uuid-a")))
    (let ((ade-core-uuid-function (lambda () "uuid-new")))
      (let ((created (ade-workspace-create-or-attach "beta" "/tmp")))
        (should (equal (ade-workspace-name created) "beta"))
        (should-not (ade-workspace-agent-ids created))
        (should (= (ade-core-workspace-count) 2)))))))

(ert-deftest ade-workspace-navigation-uses-registry-order ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-a")
    (ade-test-register-workspace "uuid-a" "alpha")
    (ade-test-register-workspace "uuid-b" "beta")
    (persp-switch "uuid-b")
    (persp-switch "uuid-a")
    (ade-test-register-workspace "uuid-c" "gamma")
    (ade-workspace-next)
    (should (equal (ade-core-current-uuid) "uuid-b"))
    (ade-workspace-prev)
    (should (equal (ade-core-current-uuid) "uuid-a"))
    (ade-workspace-prev)
    (should (equal (ade-core-current-uuid) "uuid-c"))
    (ade-workspace-select-number 1)
    (should (equal (ade-core-current-uuid) "uuid-a"))
    (should-error (ade-workspace-select-number 0) :type 'user-error))))

(ert-deftest ade-workspace-move-does-not-switch-perspective ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-a")
    (ade-test-register-workspace "uuid-a" "alpha")
    (ade-test-register-workspace "uuid-b" "beta")
    (ade-test-register-workspace "uuid-c" "gamma")
    (setq ade-test-perspective-calls nil)
    (ade-workspace-move 2)
    (should (equal (mapcar #'ade-workspace-name (ade-core-workspaces))
                   '("beta" "gamma" "alpha")))
    (should (equal (ade-core-current-uuid) "uuid-a"))
    (should-not (cl-some (lambda (call) (eq (car call) 'switch))
                         ade-test-perspective-calls)))))

(ert-deftest ade-workspace-kill-cancel-preserves-registry ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-a")
    (ade-test-register-workspace "uuid-a" "alpha")
    (should-not (ade-workspace-kill "alpha" (lambda (_name) nil)))
    (should (= (ade-core-workspace-count) 1))
    (should (ade-core-workspace-by-name "alpha"))
    (should-not (cl-some (lambda (call) (eq (car call) 'kill))
                         ade-test-perspective-calls)))))

(ert-deftest ade-workspace-kill-inactive-does-not-change-current ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-a")
    (ade-test-register-workspace "uuid-a" "alpha")
    (ade-test-register-workspace "uuid-b" "beta")
    (persp-switch "uuid-b")
    (persp-switch "uuid-a")
    (should (ade-workspace-kill "beta" (lambda (_name) t)))
    (should (equal (ade-core-current-uuid) "uuid-a"))
    (should (equal (ade-perspective-current-uuid) "uuid-a"))
    (should (= (ade-core-workspace-count) 1)))))

(ert-deftest ade-workspace-kill-active-selects-next-before-kill ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-a")
    (ade-test-register-workspace "uuid-a" "alpha")
    (ade-test-register-workspace "uuid-b" "beta")
    (ade-test-register-workspace "uuid-c" "gamma")
    (should (ade-workspace-kill "alpha" (lambda (_name) t)))
    (should (equal (ade-core-current-uuid) "uuid-b"))
    (should (equal (ade-perspective-current-uuid) "uuid-b"))
    (should-not (ade-core-workspace-by-name "alpha"))
    (should (equal (mapcar #'car ade-test-perspective-calls)
                   '(switch switch kill))))))

(ert-deftest ade-workspace-kill-failure-keeps-registry-and-restores-active ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-a")
    (ade-test-register-workspace "uuid-a" "alpha")
    (ade-test-register-workspace "uuid-b" "beta")
    (cl-letf (((symbol-function 'ade-perspective-kill)
               (lambda (_uuid) (error "injected kill failure"))))
      (should-error (ade-workspace-kill "alpha" (lambda (_name) t)))
      (should (= (ade-core-workspace-count) 2))
      (should (ade-core-workspace-by-name "alpha"))
      (should (equal (ade-core-current-uuid) "uuid-a"))
      (should (equal (ade-perspective-current-uuid) "uuid-a"))))))

(ert-deftest ade-workspace-last-kill-creates-main2-before-old-kill ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-old")
    (ade-test-register-workspace "uuid-old" "main")
    (let ((ade-core-uuid-function (lambda () "uuid-replacement")))
      (should (ade-workspace-kill "main" (lambda (_name) t)))
      (should (= (ade-core-workspace-count) 1))
      (let ((replacement (ade-core-current-workspace)))
        (should (equal (ade-workspace-name replacement) "main2"))
        (should (equal (ade-workspace-uuid replacement) "uuid-replacement"))
        (should-not (ade-core-workspace-by-name "main"))
        (should (equal (ade-perspective-current-uuid) "uuid-replacement")))
      (let* ((operations (mapcar #'car ade-test-perspective-calls))
             (create-position (cl-position 'switch operations :from-end t))
             (kill-position (cl-position 'kill operations)))
        (should create-position)
        (should kill-position)
        (should (< create-position kill-position)))))))

(ert-deftest ade-workspace-last-kill-create-failure-keeps-old ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-old")
    (ade-test-register-workspace "uuid-old" "main")
    (cl-letf (((symbol-function 'ade-perspective-create)
               (lambda (_uuid) (error "injected replacement failure"))))
      (should-error (ade-workspace-kill "main" (lambda (_name) t)))
      (should (= (ade-core-workspace-count) 1))
      (should (ade-core-workspace-by-name "main"))
      (should (equal (ade-core-current-uuid) "uuid-old"))))))

(ert-deftest ade-workspace-last-kill-old-failure-cleans-replacement ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-old")
    (ade-test-register-workspace "uuid-old" "main")
    (let ((ade-core-uuid-function (lambda () "uuid-replacement"))
          (kill-count 0))
      (cl-letf (((symbol-function 'ade-perspective-kill)
                 (lambda (_uuid)
                   (setq kill-count (1+ kill-count))
                   (when (= kill-count 1)
                     (error "injected old kill failure")))))
        (should-error (ade-workspace-kill "main" (lambda (_name) t)))
        (should (= (ade-core-workspace-count) 1))
        (should (ade-core-workspace-by-name "main"))
        (should-not (ade-core-workspace-by-name "main2"))
        (should (equal (ade-core-current-uuid) "uuid-old")))))))

(ert-deftest ade-workspace-last-kill-cleanup-failure-leaves-both ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-old")
    (ade-test-register-workspace "uuid-old" "main")
    (let ((ade-core-uuid-function (lambda () "uuid-replacement")))
      (cl-letf (((symbol-function 'ade-perspective-kill)
                 (lambda (_uuid) (error "injected kill failure"))))
        (should-error (ade-workspace-kill "main" (lambda (_name) t)))
        (should (= (ade-core-workspace-count) 2))
        (should (ade-core-workspace-by-name "main"))
        (should (ade-core-workspace-by-name "main2"))
        (should (equal (ade-core-current-uuid) "uuid-replacement")))))))

(ert-deftest ade-workspace-last-kill-main2-replacement-is-main ()
  (ade-test-with-clean-core
   (ade-test-with-perspective
    (persp-switch "uuid-old")
    (ade-test-register-workspace "uuid-old" "main2")
    (let ((ade-core-uuid-function (lambda () "uuid-replacement")))
      (ade-workspace-kill "main2" (lambda (_name) t))
      (should (equal (ade-workspace-name (ade-core-current-workspace)) "main"))
      (should-not (ade-core-workspace-by-name "main2"))))))

;;; Canonical state reducer

(ert-deftest ade-state-thread-status-maps-authoritative-statuses ()
  (should (equal (plist-get (ade-state-thread-status 'idle) :canonical)
                 'idle))
  (should (equal (plist-get (ade-state-thread-status 'active) :canonical)
                 'working))
  (should (equal (plist-get
                  (ade-state-thread-status 'active '(waitingOnApproval))
                  :canonical)
                 'blocked))
  (should (equal (plist-get
                  (ade-state-thread-status 'active '(waitingOnUserInput))
                  :canonical)
                 'blocked))
  (should (equal (plist-get (ade-state-thread-status 'systemError) :canonical)
                 'unknown))
  (should (equal (plist-get (ade-state-thread-status 'notLoaded) :canonical)
                 'unknown)))

(ert-deftest ade-state-reduce-is-pure-and-process-exit-is-not-done ()
  (let* ((state '(:canonical working :turn-origin ade :unread t))
         (next (ade-state-reduce state '(:type process-exited))) )
    (should (equal (plist-get next :canonical) 'unknown))
    (should (equal (plist-get next :lifecycle) 'exited))
    (should (equal (plist-get state :canonical) 'working)))
  (should (equal (plist-get
                  (ade-state-reduce nil '(:type turn-completed))
                  :canonical)
                 'done)))

(ert-deftest ade-state-reduce-disconnect-awaits-reconciliation ()
  (let ((next (ade-state-reduce '(:canonical working :turn-origin ade)
                                '(:type connection-lost))))
    (should (equal (plist-get next :canonical) 'unknown))
    (should (equal (plist-get next :reason) 'connection-lost))
    (should (equal (plist-get next :lifecycle) 'disconnected)))
  (let ((next (ade-state-reduce '(:canonical unknown :turn-origin ade)
                                '(:type connection-restored))))
    (should (equal (plist-get next :canonical) 'unknown))
    (should (equal (plist-get next :reason) 'awaiting-reconciliation))))

(ert-deftest ade-state-rollup-obeys-priority-and-unknown-safety ()
  (should (eq (ade-state-rollup nil) 'no-agent))
  (should (eq (ade-state-rollup '((:canonical idle))) 'idle))
  (should (eq (ade-state-rollup '((:canonical done) (:canonical idle))) 'done))
  (should (eq (ade-state-rollup '((:canonical done) (:canonical unknown)))
             'unknown))
  (should (eq (ade-state-rollup '((:canonical working) (:canonical unknown)))
             'working))
  (should (eq (ade-state-rollup '((:canonical blocked) (:canonical working)))
             'blocked))
  (should (eq (ade-state-rollup
               (list (ade-test-agent "a" nil "t" 'done)))
              'done)))

(ert-deftest ade-state-control-allowed-requires-origin-boundary ()
  (should (ade-state-control-allowed-p '(:canonical idle :turn-origin ade)
                                       'start))
  (should-not (ade-state-control-allowed-p
               '(:canonical idle :turn-origin unknown) 'start))
  (should (ade-state-control-allowed-p
           '(:canonical working :turn-origin ade) 'steer))
  (should-not (ade-state-control-allowed-p
               '(:canonical working :turn-origin tui) 'steer))
  (should (ade-state-control-allowed-p
           '(:canonical blocked :turn-origin tui) 'respond)))

(ert-deftest ade-state-apply-event-updates-agent-and-hook ()
  (let ((events nil)
        (agent (ade-agent-create :id "agent-a"
                                 :workspace-uuid "uuid-a"
                                 :thread-id "thread-a"
                                 :state 'idle
                                 :turn-origin 'ade)))
    (let ((ade-state-change-hook
           (list (lambda (changed event)
                   (setq events (list changed event))))))
      (ade-state-apply-event agent
                             '(:type thread-status
                               :status active
                               :source app-server))
      (should (eq (ade-agent-state agent) 'working))
      (should (eq (ade-agent-source agent) 'app-server))
      (should (eq (car events) agent))
      (should (equal (plist-get (cadr events) :type) 'thread-status)))))

(provide 'ade-core-test)

;;; ade-core-test.el ends here
