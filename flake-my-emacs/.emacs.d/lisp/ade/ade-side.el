;;; ade-side.el --- ADE-owned ephemeral fork handling -*- lexical-binding: t; -*-

;;; Commentary:

;; App Server has no semantic TUI side-channel method.  ADE can therefore
;; mark a side as known only when it explicitly creates an ephemeral fork and
;; verifies `forkedFromId'.  A side merely seen in terminal output remains
;; unknown and cannot be sent to or closed.

;;; Code:

(require 'cl-lib)
(require 'ade-agent)
(require 'ade-app-server)
(require 'ade-ghostel)

(defgroup ade-side nil
  "Known ADE-owned ephemeral side threads."
  :group 'ade)

(define-error 'ade-side-error "ADE side error" 'ade-error)
(define-error 'ade-side-unknown-error
  "ADE side identity is unknown"
  'ade-side-error)

(cl-defstruct (ade-side
               (:constructor ade-side--make))
  "A verified ADE-owned ephemeral fork."
  agent-id main-thread-id thread-id session-id model ephemeral-p forked-from-id
  verified-p closed-p state metadata)

(defvar ade-side--table (make-hash-table :test #'equal)
  "Known side records indexed by (Agent-ID . side-thread-id).")

(defun ade-side-reset ()
  "Clear the session-local side registry; intended for tests."
  (setq ade-side--table (make-hash-table :test #'equal))
  t)

(defun ade-side--json-get (object key)
  "Return KEY from an alist or plist OBJECT."
  (let* ((name (cond
                ((keywordp key) (substring (symbol-name key) 1))
                ((symbolp key) (symbol-name key))
                (t key)))
         (symbol (and (stringp name) (intern name)))
         (keyword (and (stringp name) (intern (concat ":" name)))))
    (and (listp object)
         (or (alist-get symbol object nil nil #'equal)
             (alist-get name object nil nil #'equal)
             (plist-get object keyword)
             (plist-get object symbol)))))

(defun ade-side--key (agent-id thread-id)
  "Return the registry key for AGENT-ID and THREAD-ID."
  (cons agent-id thread-id))

(defun ade-side-by-thread (agent thread-id)
  "Return verified side THREAD-ID belonging to AGENT, or nil."
  (gethash (ade-side--key (ade-agent-id agent) thread-id) ade-side--table))

(defun ade-side-known-p (agent &optional thread-id)
  "Return non-nil only for a verified ADE-created side."
  (let ((thread-id (or thread-id (ade-agent-side-thread-id agent))))
    (and thread-id
         (let ((side (ade-side-by-thread agent thread-id)))
           (and side (ade-side-verified-p side) (not (ade-side-closed-p side)))))))

(defun ade-side--model (agent)
  "Return the explicit main-thread model required for a fork."
  (let ((model (ade-agent-model agent)))
    (unless (and (stringp model) (not (string-empty-p model)))
      (signal 'ade-side-error
              (list "Main thread model is unavailable; refusing implicit fork"
                    agent)))
    model))

(defun ade-side-create (agent &optional callback errorback)
  "Create and verify an ADE-owned ephemeral side fork for AGENT.

The main model is always included explicitly so App Server's default model
cannot silently replace it.  CALLBACK receives the verified `ade-side'."
  (let ((connection (ade-agent-connection agent))
        (main-thread-id (or (ade-agent-main-thread-id agent)
                            (ade-agent-thread-id agent))))
    (unless (and connection (ade-app-server-connected-p connection))
      (signal 'ade-side-error (list "Agent App Server connection is not ready")))
    (unless main-thread-id
      (signal 'ade-side-error (list "Agent has no main thread id")))
    (let ((model (ade-side--model agent)))
      (ade-app-server-call
       connection "thread/fork"
       (list (cons 'threadId main-thread-id)
             (cons 'ephemeral t)
             (cons 'model model)
             (cons 'excludeTurns t))
       (lambda (result)
         (let* ((thread (ade-side--json-get result 'thread))
                (thread-id (ade-side--json-get thread 'id))
                (forked-from (ade-side--json-get thread 'forkedFromId))
                (ephemeral (ade-side--json-get thread 'ephemeral)))
           (unless (and thread-id ephemeral
                        (equal forked-from main-thread-id))
             (signal 'ade-side-error
                     (list "App Server returned an unverifiable side fork"
                           result)))
           (let ((side
                  (ade-side--make
                   :agent-id (ade-agent-id agent)
                   :main-thread-id main-thread-id
                   :thread-id thread-id
                   :session-id (ade-side--json-get thread 'sessionId)
                   :model (or (ade-side--json-get thread 'model) model)
                   :ephemeral-p t
                   :forked-from-id forked-from
                   :verified-p t
                   :closed-p nil
                   :state 'idle
                   :metadata nil)))
             (puthash (ade-side--key (ade-agent-id agent) thread-id)
                      side ade-side--table)
             (setf (ade-agent-side-thread-id agent) thread-id)
             (when callback (funcall callback side))
             side)))
       (lambda (error)
         (when errorback (funcall errorback error agent)))))))

(defun ade-side--assert-known (agent &optional thread-id)
  "Return a verified side or signal for AGENT and THREAD-ID."
  (let* ((thread-id (or thread-id (ade-agent-side-thread-id agent)))
         (side (and thread-id (ade-side-by-thread agent thread-id))))
    (unless (and side (ade-side-verified-p side) (not (ade-side-closed-p side)))
      (signal 'ade-side-unknown-error
              (list "TUI/unknown side cannot be controlled" thread-id)))
    side))

(defun ade-side-send (agent text &optional callback errorback)
  "Send TEXT to a verified ADE-owned side only."
  (let* ((side (ade-side--assert-known agent))
         (connection (ade-agent-connection agent))
         (client-id (format "ade-side-%s-%x"
                            (ade-side-thread-id side)
                            (truncate (* 1000000 (float-time))))))
    (ade-app-server-call
     connection "turn/start"
     (list (cons 'threadId (ade-side-thread-id side))
           (cons 'input
                 (vector (list (cons 'type "text")
                               (cons 'text text))))
           (cons 'clientUserMessageId client-id)
           (cons 'turnTrigger "ade"))
     (lambda (result)
       (setf (ade-side-state side) 'working)
       (when callback (funcall callback side result)))
     (lambda (error)
       (when errorback (funcall errorback side error))))))

(defun ade-side-close (agent &optional callback)
  "Mark an ADE-owned side closed without guessing a TUI close protocol.

There is no semantic App Server `side/close' method.  Closing a known
ephemeral side therefore only removes ADE control after any caller-visible
interrupt/cleanup has been handled explicitly.  Unknown/TUI sides signal."
  (let ((side (ade-side--assert-known agent)))
    (setf (ade-side-closed-p side) t
          (ade-side-verified-p side) nil
          (ade-side-state side) 'unknown)
    (when (equal (ade-agent-side-thread-id agent) (ade-side-thread-id side))
      (setf (ade-agent-side-thread-id agent) nil))
    (when callback (funcall callback side))
    side))

(defun ade-side-mark-tui-unknown (agent)
  "Return an unknown TUI side marker without registering an identity."
  (ignore agent)
  nil)

(defun ade-side-toggle-tui (agent)
  "Send semantic Ctrl-/ to AGENT's TUI without claiming side identity."
  ;; Control slash is a Ghostel key operation, not raw ASCII SIGINT.  The
  ;; resulting TUI side remains unknown until ADE explicitly forks/verifies.
  (ade-ghostel-send-key agent "/" "ctrl"))

(provide 'ade-side)

;;; ade-side.el ends here
