;;; ade-core.el --- Session-local ADE data and registry -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shuto Omura

;;; Commentary:

;; This file deliberately contains no Perspective, App Server, Ghostel, or UI
;; calls.  It is the small in-memory kernel shared by the ADE adapters.  The
;; registry is intentionally not persisted: an Emacs restart starts a fresh
;; ADE session.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup ade nil
  "A session-local Codex agent development environment."
  :group 'convenience)

(define-error 'ade-error "ADE error")
(define-error 'ade-invariant-error "ADE invariant violation" 'ade-error)
(define-error 'ade-name-conflict-error "ADE human name is already in use"
  'ade-error)
(define-error 'ade-not-found-error "ADE object was not found" 'ade-error)
(define-error 'ade-invalid-selection-error "ADE selection is invalid" 'ade-error)
(define-error 'ade-no-current-workspace-error
  "ADE has no current Workspace"
  'ade-error)
(define-error 'ade-unsupported-error "ADE operation is unsupported" 'ade-error)

(defconst ade-canonical-states '(working blocked done idle unknown)
  "Canonical Agent states understood by ADE.

Lifecycle details such as `starting' or `exited' belong in metadata and are
not additional canonical states.")

(defconst ade-turn-origins '(ade tui unknown)
  "Known origins of Codex turns.")

(defcustom ade-core-uuid-function nil
  "Optional function used to generate an ADE UUID.

The function is useful for deterministic tests.  It must return a non-empty
string and takes no arguments.  When nil, ADE generates a UUID-like value
without invoking an external command."
  :type '(choice (const :tag "Built-in generator" nil) function)
  :group 'ade)

(cl-defstruct (ade-workspace
               (:constructor ade-workspace-create
                             (&key uuid name root worktree perspective-name
                                   prompt-buffer agent-ids selected-agent-id
                                   metadata)))
  "An ADE Workspace and its Perspective identity.

`uuid' is the immutable underlying Perspective name.  `name' is the
human-facing name owned by the ADE registry."
  uuid name root worktree perspective-name prompt-buffer agent-ids
  selected-agent-id metadata)

(cl-defstruct (ade-agent
               (:constructor ade-agent-create
                             (&key id workspace-uuid thread-id session-id
                                   main-thread-id side-thread-id buffer process
                                   connection state reason source observed-at
                                   latest-event unread-p pending-requests
                                   turn-origin lifecycle model effort
                                   detached-p metadata)))
  "An ADE Agent record.

The logical Codex `thread-id' is the identity correlation anchor.  Buffer and
process fields are auxiliary attachment metadata, never identity guesses."
  id workspace-uuid thread-id session-id main-thread-id side-thread-id buffer
  process connection state reason source observed-at latest-event unread-p
  pending-requests turn-origin lifecycle model effort detached-p metadata)

(defvar ade-core--workspaces (make-hash-table :test #'equal)
  "Workspace records indexed by immutable UUID.")
(defvar ade-core--name-index (make-hash-table :test #'equal)
  "Human-facing Workspace names indexed by name.")
(defvar ade-core--agents (make-hash-table :test #'equal)
  "Agent records indexed by stable ADE Agent ID.")
(defvar ade-core--thread-index (make-hash-table :test #'equal)
  "Agent IDs indexed by logical Codex thread ID.")
(defvar ade-core--detached-agents (make-hash-table :test #'equal)
  "Detached Agent records retained while their process/buffer exists.")
(defvar ade-core--order nil
  "Workspace UUIDs in explicit ADE display/navigation order.")
(defvar ade-core--current-uuid nil
  "UUID of the current ADE Workspace, or nil before initialization.")

(defun ade-core--non-empty-string-p (value)
  "Return non-nil when VALUE is a non-empty string."
  (and (stringp value) (not (string-empty-p value))))

(defun ade-core--uuid-like-p (value)
  "Return non-nil when VALUE is a UUID-like non-empty string.

The registry does not require one particular UUID version, but rejecting
whitespace and empty values catches accidental human labels being used as the
underlying Perspective key."
  (and (ade-core--non-empty-string-p value)
       (not (string-match-p "[[:space:]]" value))))

(defun ade-core--default-uuid ()
  "Generate a UUID-like value without relying on an external executable."
  (let* ((seed (format "%s:%s:%s:%s"
                      (float-time)
                      (emacs-pid)
                      (random)
                      (user-uid)))
         (digest (md5 seed)))
    (format "%s-%s-4%s-%s-%s"
            (substring digest 0 8)
            (substring digest 8 12)
            (substring digest 13 16)
            (substring digest 16 20)
            (substring digest 20 32))))

(defun ade-core-generate-uuid ()
  "Return a new UUID-like underlying Perspective name."
  (let ((uuid (if ade-core-uuid-function
                 (funcall ade-core-uuid-function)
               (ade-core--default-uuid))))
    (unless (ade-core--uuid-like-p uuid)
      (signal 'ade-invariant-error
              (list "UUID generator returned an invalid value" uuid)))
    (when (gethash uuid ade-core--workspaces)
      (signal 'ade-invariant-error
              (list "UUID generator returned an existing value" uuid)))
    uuid))

(defun ade-core-reset ()
  "Reset all ADE session state.

This is intended for a fresh session and tests.  It does not touch any
Perspective or external process and does not write a file."
  (setq ade-core--workspaces (make-hash-table :test #'equal)
        ade-core--name-index (make-hash-table :test #'equal)
        ade-core--agents (make-hash-table :test #'equal)
        ade-core--thread-index (make-hash-table :test #'equal)
        ade-core--detached-agents (make-hash-table :test #'equal)
        ade-core--order nil
        ade-core--current-uuid nil)
  t)

(defun ade-core-workspaces ()
  "Return Workspace records in explicit ADE order."
  (mapcar (lambda (uuid) (gethash uuid ade-core--workspaces))
          ade-core--order))

(defun ade-core-workspace-count ()
  "Return the number of registered Workspaces."
  (length ade-core--order))

(defun ade-core-current-workspace ()
  "Return the current Workspace, or nil."
  (and ade-core--current-uuid
       (gethash ade-core--current-uuid ade-core--workspaces)))

(defun ade-core-current-uuid ()
  "Return the current Workspace UUID, or nil."
  ade-core--current-uuid)

(defun ade-core-set-current (uuid)
  "Set the current Workspace to UUID and return its record."
  (unless (gethash uuid ade-core--workspaces)
    (signal 'ade-not-found-error (list "Workspace UUID" uuid)))
  (setq ade-core--current-uuid uuid)
  (gethash uuid ade-core--workspaces))

(defun ade-core-workspace-by-uuid (uuid)
  "Return the Workspace identified by UUID, or nil."
  (gethash uuid ade-core--workspaces))

(defun ade-core-workspace-by-name (name)
  "Return the Workspace identified by human-facing NAME, or nil."
  (when-let* ((uuid (gethash name ade-core--name-index)))
    (gethash uuid ade-core--workspaces)))

(defun ade-core-workspace-index (uuid)
  "Return the zero-based order index of UUID, or nil."
  (cl-position uuid ade-core--order :test #'equal))

(defun ade-core-agent-by-id (id)
  "Return the Agent identified by stable ADE ID, or nil."
  (gethash id ade-core--agents))

(defun ade-core-agent-by-thread (thread-id)
  "Return the Agent associated with logical THREAD-ID, or nil."
  (when-let* ((id (gethash thread-id ade-core--thread-index)))
    (gethash id ade-core--agents)))

(defun ade-core-detached-agent-by-id (id)
  "Return detached Agent ID, or nil."
  (gethash id ade-core--detached-agents))

(defun ade-core--check-workspace (workspace)
  "Signal when WORKSPACE cannot be registered."
  (unless (ade-workspace-p workspace)
    (signal 'ade-invariant-error (list "Not an ADE Workspace" workspace)))
  (unless (ade-core--uuid-like-p (ade-workspace-uuid workspace))
    (signal 'ade-invariant-error (list "Invalid Workspace UUID" workspace)))
  (unless (ade-core--non-empty-string-p (ade-workspace-name workspace))
    (signal 'ade-invariant-error (list "Workspace name is empty" workspace)))
  (unless (stringp (ade-workspace-root workspace))
    (signal 'ade-invariant-error (list "Workspace root is not a string" workspace)))
  (dolist (agent-id (ade-workspace-agent-ids workspace))
    (unless (ade-core--non-empty-string-p agent-id)
      (signal 'ade-invariant-error (list "Invalid Agent ID" agent-id))))
  workspace)

(defun ade-core-register-workspace (workspace)
  "Register WORKSPACE in ADE order.

Human-facing names and underlying UUIDs must both be unique.  The first
Workspace becomes current; callers that are switching an existing Perspective
should call `ade-core-set-current' explicitly."
  (ade-core--check-workspace workspace)
  (let ((uuid (ade-workspace-uuid workspace))
        (name (ade-workspace-name workspace)))
    (when (gethash uuid ade-core--workspaces)
      (signal 'ade-name-conflict-error (list "Workspace UUID" uuid)))
    (when (gethash name ade-core--name-index)
      (signal 'ade-name-conflict-error (list "Workspace name" name)))
    (when (ade-workspace-selected-agent-id workspace)
      (unless (member (ade-workspace-selected-agent-id workspace)
                      (ade-workspace-agent-ids workspace))
        (signal 'ade-invalid-selection-error
                (list "Selected Agent is not a Workspace member" workspace))))
    (puthash uuid workspace ade-core--workspaces)
    (puthash name uuid ade-core--name-index)
    (setq ade-core--order (append ade-core--order (list uuid)))
    (unless ade-core--current-uuid
      (setq ade-core--current-uuid uuid))
    (ade-core-validate)
    workspace))

(defun ade-core-rename-workspace (uuid new-name)
  "Replace UUID's human-facing name with NEW-NAME.

The underlying UUID, Perspective, Prompt, Agent membership, and selected
Agent are unchanged.  The old name is not retained as an alias."
  (let ((workspace (ade-core-workspace-by-uuid uuid)))
    (unless workspace
      (signal 'ade-not-found-error (list "Workspace UUID" uuid)))
    (unless (ade-core--non-empty-string-p new-name)
      (signal 'ade-invariant-error (list "Workspace name is empty" new-name)))
    (when (gethash new-name ade-core--name-index)
      (signal 'ade-name-conflict-error (list "Workspace name" new-name)))
    (remhash (ade-workspace-name workspace) ade-core--name-index)
    (setf (ade-workspace-name workspace) new-name)
    (puthash new-name uuid ade-core--name-index)
    (ade-core-validate)
    workspace))

(defun ade-core-unregister-workspace (uuid)
  "Remove UUID from the registry and return the removed Workspace.

The Perspective must already have been destroyed successfully.  This function
only changes session registry state; Workspace lifecycle code is responsible
for calling it at the correct transaction boundary."
  (let ((workspace (ade-core-workspace-by-uuid uuid)))
    (unless workspace
      (signal 'ade-not-found-error (list "Workspace UUID" uuid)))
    ;; Perspective cleanup is intentionally performed by the caller first.
    ;; Agent records survive Workspace deletion as detached session records;
    ;; no process stop/abort is implied by this registry operation.
    (dolist (agent-id (copy-sequence (ade-workspace-agent-ids workspace)))
      (when-let* ((agent (ade-core-agent-by-id agent-id)))
        (setf (ade-agent-workspace-uuid agent) nil
              (ade-agent-detached-p agent) t)
        (puthash agent-id agent ade-core--detached-agents)))
    (remhash uuid ade-core--workspaces)
    (remhash (ade-workspace-name workspace) ade-core--name-index)
    (setq ade-core--order (delete uuid ade-core--order))
    (when (equal ade-core--current-uuid uuid)
      (setq ade-core--current-uuid nil))
    (ade-core-validate)
    workspace))

(defun ade-core--workspace-for-agent (agent-id)
  "Return the Workspace containing AGENT-ID, or nil."
  (cl-find-if (lambda (workspace)
                (member agent-id (ade-workspace-agent-ids workspace)))
              (ade-core-workspaces)))

(defun ade-core-register-agent (agent &optional explicit-selection-p)
  "Register AGENT and attach it to its Workspace.

The first passive registration initializes selected.  Later passive
registrations preserve the existing selection.  Explicit start/attach calls
pass EXPLICIT-SELECTION-P and always select the newly registered Agent."
  (unless (ade-agent-p agent)
    (signal 'ade-invariant-error (list "Not an ADE Agent" agent)))
    (let* ((agent-id (ade-agent-id agent))
           (workspace-uuid (ade-agent-workspace-uuid agent))
           (workspace (ade-core-workspace-by-uuid workspace-uuid)))
    (cl-block ade-core-register-agent
      (unless (ade-core--non-empty-string-p agent-id)
        (signal 'ade-invariant-error (list "Agent ID is empty" agent)))
      (unless workspace
        (signal 'ade-not-found-error (list "Agent Workspace" workspace-uuid)))
      (let ((existing (gethash agent-id ade-core--agents)))
      (when existing
        ;; Explicit attach/start may select an already registered Agent, but a
        ;; second logical identity must not silently replace it.
        (unless (equal workspace-uuid
                       (ade-agent-workspace-uuid existing))
          (signal 'ade-name-conflict-error
                  (list "Agent ID belongs to another Workspace" agent-id)))
        (when (and (ade-agent-thread-id agent)
                   (ade-agent-thread-id existing)
                   (not (equal (ade-agent-thread-id agent)
                               (ade-agent-thread-id existing))))
          (signal 'ade-name-conflict-error (list "Agent ID" agent-id)))
        (when explicit-selection-p
          (ade-core-select-agent workspace-uuid agent-id))
        (cl-return-from ade-core-register-agent existing)))
      (when-let* ((thread-id (ade-agent-thread-id agent)))
        (when-let* ((existing-id (gethash thread-id ade-core--thread-index)))
          (if (equal existing-id agent-id)
              (cl-return-from ade-core-register-agent
                (ade-core-agent-by-id existing-id))
            (let ((existing (ade-core-agent-by-id existing-id)))
              (if (and existing
                       (equal workspace-uuid
                              (ade-agent-workspace-uuid existing)))
                  (progn
                    ;; Thread identity wins over a newly allocated wrapper ID:
                    ;; a TUI reconnect remains the same ADE Agent.
                    (setf (ade-agent-id agent) existing-id)
                    (cl-return-from ade-core-register-agent
                      (ade-core-update-agent agent)))
                (signal 'ade-name-conflict-error
                        (list "Agent thread ID" thread-id)))))))
      (puthash agent-id agent ade-core--agents)
      (when-let* ((thread-id (ade-agent-thread-id agent)))
        (puthash thread-id agent-id ade-core--thread-index))
      (setf (ade-workspace-agent-ids workspace)
            (append (ade-workspace-agent-ids workspace) (list agent-id)))
      (when (or explicit-selection-p
                (null (ade-workspace-selected-agent-id workspace)))
        (setf (ade-workspace-selected-agent-id workspace) agent-id))
      (remhash agent-id ade-core--detached-agents)
      (setf (ade-agent-detached-p agent) nil)
      (ade-core-validate)
      agent)))

(defun ade-core-update-agent (agent)
  "Replace the existing Agent record with AGENT while preserving membership.

This is used for a same-thread TUI reconnect.  The caller must keep the same
stable ADE Agent ID."
  (unless (ade-agent-p agent)
    (signal 'ade-invariant-error (list "Not an ADE Agent" agent)))
  (let ((old (ade-core-agent-by-id (ade-agent-id agent))))
    (unless old
      (signal 'ade-not-found-error (list "Agent ID" (ade-agent-id agent))))
    (unless (equal (ade-agent-workspace-uuid old)
                   (ade-agent-workspace-uuid agent))
      (signal 'ade-invariant-error
              (list "Reconnect changed Agent Workspace"
                    (ade-agent-id agent))))
    (when (and (ade-agent-thread-id old)
               (ade-agent-thread-id agent)
               (not (equal (ade-agent-thread-id old)
                           (ade-agent-thread-id agent))))
      (when-let* ((other (ade-core-agent-by-thread (ade-agent-thread-id agent))))
        (unless (equal (ade-agent-id other) (ade-agent-id agent))
          (signal 'ade-name-conflict-error
                  (list "Agent thread ID" (ade-agent-thread-id agent))))))
    (when-let* ((old-thread (ade-agent-thread-id old)))
      (remhash old-thread ade-core--thread-index))
    (when-let* ((new-thread (ade-agent-thread-id agent)))
      (puthash new-thread (ade-agent-id agent) ade-core--thread-index))
    (puthash (ade-agent-id agent) agent ade-core--agents)
    (ade-core-validate)
    agent))

(defun ade-core-select-agent (workspace-uuid agent-id)
  "Select AGENT-ID in WORKSPACE-UUID.

Selection is Workspace-local and is the only normal ADE send target concept."
  (let ((workspace (ade-core-workspace-by-uuid workspace-uuid))
        (agent (ade-core-agent-by-id agent-id)))
    (unless workspace
      (signal 'ade-not-found-error (list "Workspace UUID" workspace-uuid)))
    (unless (and agent (member agent-id (ade-workspace-agent-ids workspace)))
      (signal 'ade-invalid-selection-error
              (list "Agent is not a member of Workspace" agent-id)))
    (setf (ade-workspace-selected-agent-id workspace) agent-id)
    (ade-core-validate)
    agent))

(defun ade-core-clear-selected-agent (workspace-uuid &optional agent-id)
  "Clear selected Agent in WORKSPACE-UUID.

When AGENT-ID is supplied, clear only when it is currently selected."
  (when-let* ((workspace (ade-core-workspace-by-uuid workspace-uuid)))
    (when (or (null agent-id)
              (equal agent-id (ade-workspace-selected-agent-id workspace)))
      (setf (ade-workspace-selected-agent-id workspace) nil))
    (ade-core-validate)
    workspace))

(defun ade-core-detach-agent (agent-id)
  "Detach AGENT-ID from its Workspace without deleting its record.

The record is moved to the detached registry and remains available while its
process/buffer exists."
  (let* ((agent (ade-core-agent-by-id agent-id))
         (workspace (and agent
                         (ade-core--workspace-for-agent agent-id))))
    (unless agent
      (signal 'ade-not-found-error (list "Agent ID" agent-id)))
    (when workspace
      (setf (ade-workspace-agent-ids workspace)
            (delete agent-id (ade-workspace-agent-ids workspace)))
      (when (equal agent-id (ade-workspace-selected-agent-id workspace))
        (setf (ade-workspace-selected-agent-id workspace) nil)))
    (setf (ade-agent-workspace-uuid agent) nil
          (ade-agent-detached-p agent) t)
    (puthash agent-id agent ade-core--detached-agents)
    (ade-core-validate)
    agent))

(defun ade-core-attach-agent (agent-id workspace-uuid &optional explicit-selection-p)
  "Attach detached AGENT-ID to WORKSPACE-UUID.

Reattachment is unselected by default.  Explicit attach/start can pass
EXPLICIT-SELECTION-P to select it."
  (let ((agent (ade-core-agent-by-id agent-id))
        (workspace (ade-core-workspace-by-uuid workspace-uuid)))
    (unless agent
      (signal 'ade-not-found-error (list "Agent ID" agent-id)))
    (unless workspace
      (signal 'ade-not-found-error (list "Workspace UUID" workspace-uuid)))
    (let ((attached (ade-core--workspace-for-agent agent-id)))
      (when (and attached (not (eq attached workspace)))
        (signal 'ade-invariant-error
                (list "Agent is already attached to another Workspace"
                      agent-id)))
      (unless (or (ade-agent-detached-p agent)
                  (eq attached workspace))
        (signal 'ade-invariant-error
                (list "Agent is not detached" agent-id)))
      (unless (member agent-id (ade-workspace-agent-ids workspace))
        (setf (ade-workspace-agent-ids workspace)
              (append (ade-workspace-agent-ids workspace) (list agent-id)))))
    (setf (ade-agent-workspace-uuid agent) workspace-uuid
          (ade-agent-detached-p agent) nil)
    (remhash agent-id ade-core--detached-agents)
    (when explicit-selection-p
      (setf (ade-workspace-selected-agent-id workspace) agent-id))
    (ade-core-validate)
    agent))

(defun ade-core-reorder (uuid target-index)
  "Move UUID to zero-based TARGET-INDEX, clamped to registry bounds.

The current Workspace and Perspective are not changed."
  (unless (gethash uuid ade-core--workspaces)
    (signal 'ade-not-found-error (list "Workspace UUID" uuid)))
  (let* ((old-index (ade-core-workspace-index uuid))
         (max-index (max 0 (1- (length ade-core--order))))
         (index (max 0 (min max-index target-index))))
    (unless (equal old-index index)
      (setq ade-core--order (delete uuid ade-core--order))
      (setq ade-core--order
            (append (cl-subseq ade-core--order 0 index)
                    (list uuid)
                    (cl-subseq ade-core--order index))))
    (ade-core-validate)
    (gethash uuid ade-core--workspaces)))

(defun ade-core-move-current (delta)
  "Move the current Workspace by DELTA positions, clamped at the ends."
  (unless ade-core--current-uuid
    (signal 'ade-no-current-workspace-error nil))
  (let ((index (ade-core-workspace-index ade-core--current-uuid)))
    (ade-core-reorder ade-core--current-uuid (+ index delta))))

(defun ade-core-adjacent-uuid (uuid direction)
  "Return adjacent UUID from UUID in DIRECTION, wrapping at either end.

DIRECTION must be 1 or -1.  Return nil for an empty registry."
  (unless (memq direction '(1 -1))
    (signal 'ade-invariant-error (list "Direction must be 1 or -1" direction)))
  (when ade-core--order
    (let* ((index (or (ade-core-workspace-index uuid)
                      (signal 'ade-not-found-error (list "Workspace UUID" uuid))))
           (length (length ade-core--order)))
      (nth (mod (+ index direction) length) ade-core--order))))

(defun ade-core-validate ()
  "Signal unless all session registry invariants hold.

This function intentionally performs only in-memory checks and is called after
mutating registry operations.  It is also public so tests and diagnostics can
assert the invariants at transaction boundaries."
  (let ((seen-names (make-hash-table :test #'equal))
        (seen-uuids (make-hash-table :test #'equal)))
    (unless (= (hash-table-count ade-core--workspaces)
               (length ade-core--order))
      (signal 'ade-invariant-error
              (list "Workspace hash and order lengths differ")))
    (unless (= (hash-table-count ade-core--workspaces)
               (hash-table-count ade-core--name-index))
      (signal 'ade-invariant-error
              (list "Workspace hash and name index lengths differ")))
    (dolist (uuid ade-core--order)
      (when (gethash uuid seen-uuids)
        (signal 'ade-invariant-error (list "Duplicate UUID in order" uuid)))
      (puthash uuid t seen-uuids)
      (let ((workspace (gethash uuid ade-core--workspaces)))
        (unless workspace
          (signal 'ade-invariant-error
                  (list "Order contains unknown UUID" uuid)))
        (ade-core--check-workspace workspace)
        (unless (or (null (ade-workspace-perspective-name workspace))
                    (equal uuid (ade-workspace-perspective-name workspace)))
          (signal 'ade-invariant-error
                  (list "Perspective name and UUID differ" uuid)))
        (let ((seen-agent-ids (make-hash-table :test #'equal)))
          (dolist (agent-id (ade-workspace-agent-ids workspace))
            (when (gethash agent-id seen-agent-ids)
              (signal 'ade-invariant-error
                      (list "Duplicate Agent in Workspace" agent-id)))
            (puthash agent-id t seen-agent-ids)
            (let ((agent (gethash agent-id ade-core--agents)))
              (unless agent
                (signal 'ade-invariant-error
                        (list "Workspace contains unknown Agent" agent-id)))
              (unless (and (equal uuid (ade-agent-workspace-uuid agent))
                           (not (ade-agent-detached-p agent)))
                (signal 'ade-invariant-error
                        (list "Workspace Agent membership mismatch" agent-id))))))
        (let ((name (ade-workspace-name workspace)))
          (when (gethash name seen-names)
            (signal 'ade-invariant-error (list "Duplicate name" name)))
          (puthash name t seen-names)
          (unless (equal uuid (gethash name ade-core--name-index))
            (signal 'ade-invariant-error
                    (list "Name index does not point to Workspace" name))))
        (let ((selected (ade-workspace-selected-agent-id workspace)))
          (when (and selected
                     (not (member selected (ade-workspace-agent-ids workspace))))
            (signal 'ade-invariant-error
                    (list "Selected Agent is not a member" selected))))))
    (when (and ade-core--current-uuid
               (not (gethash ade-core--current-uuid ade-core--workspaces)))
      (signal 'ade-invariant-error
              (list "Current UUID is not registered" ade-core--current-uuid)))
    (maphash
     (lambda (name uuid)
       (unless (and (gethash uuid ade-core--workspaces)
                    (equal name
                           (ade-workspace-name
                            (gethash uuid ade-core--workspaces))))
         (signal 'ade-invariant-error
                 (list "Name index contains an invalid entry" name))))
     ade-core--name-index)
    (maphash
     (lambda (agent-id agent)
       (unless (equal agent-id (ade-agent-id agent))
         (signal 'ade-invariant-error (list "Agent hash key mismatch" agent-id)))
       (when-let* ((thread-id (ade-agent-thread-id agent)))
         (unless (equal agent-id (gethash thread-id ade-core--thread-index))
           (signal 'ade-invariant-error
                   (list "Thread index mismatch" thread-id))))
       (let ((workspace-uuid (ade-agent-workspace-uuid agent)))
         (if workspace-uuid
             (let ((workspace (gethash workspace-uuid ade-core--workspaces)))
               (unless (and workspace
                            (member agent-id (ade-workspace-agent-ids workspace))
                            (not (ade-agent-detached-p agent))
                            (not (gethash agent-id ade-core--detached-agents)))
                 (signal 'ade-invariant-error
                         (list "Agent membership mismatch" agent-id))))
           (unless (and (ade-agent-detached-p agent)
                        (eq agent (gethash agent-id ade-core--detached-agents)))
             (signal 'ade-invariant-error
                     (list "Detached Agent registry mismatch" agent-id))))))
     ade-core--agents)
    (maphash
     (lambda (thread-id agent-id)
       (let ((agent (gethash agent-id ade-core--agents)))
         (unless (and agent
                      (equal thread-id (ade-agent-thread-id agent)))
           (signal 'ade-invariant-error
                   (list "Thread index contains an invalid entry" thread-id)))))
     ade-core--thread-index)
    (maphash
     (lambda (agent-id agent)
       (unless (and (eq agent (gethash agent-id ade-core--agents))
                    (ade-agent-detached-p agent)
                    (null (ade-agent-workspace-uuid agent)))
         (signal 'ade-invariant-error
                 (list "Detached registry contains an invalid Agent" agent-id))))
     ade-core--detached-agents)
    t))

(provide 'ade-core)

;;; ade-core.el ends here
