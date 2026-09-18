;;; ade-send.el --- Origin-bound turn delivery for ADE -*- lexical-binding: t; -*-

;;; Commentary:

;; Normal ADE delivery is App Server JSON-RPC, never terminal prose or key
;; injection.  Every ADE-started turn gets a clientUserMessageId and
;; turnTrigger marker.  TUI/unknown turns are monitor-only unless a caller
;; explicitly performs a takeover confirmation.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ade-agent)
(require 'ade-app-server)

(defgroup ade-send nil
  "Origin-bound Codex turn delivery."
  :group 'ade)

(define-error 'ade-send-error "ADE send error" 'ade-error)
(define-error 'ade-send-not-allowed-error
  "ADE send is not allowed for this Agent"
  'ade-send-error)

(defcustom ade-send-takeover-confirm-function nil
  "Optional function used to confirm an unknown-to-ADE takeover.

The function receives an Agent and returns non-nil only after an explicit
human choice.  Nil means that unknown-origin Agents remain monitor-only."
  :type '(choice (const :tag "Require caller's explicit :takeover" nil)
                 function)
  :group 'ade-send)

(cl-defstruct (ade-send-snapshot
               (:constructor ade-send-snapshot--make))
  "Identity snapshot used by an accepted-send callback."
  agent-id thread-id turn-id client-user-message-id generation)

(defun ade-send--json-get (object key)
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

(defun ade-send--normalize-input (text)
  "Convert TEXT or an input list to App Server UserInput values."
  ;; `json-serialize' uses vectors for JSON arrays; a nested Lisp list is
  ;; otherwise interpreted as another object and signals on its first pair.
  (cond
   ((vectorp text) text)
   ((listp text) (vconcat text))
   (t (vector (list (cons 'type "text") (cons 'text text))))))

(defun ade-send--new-client-id (agent)
  "Return a unique ADE clientUserMessageId for AGENT."
  (format "ade-%s-%x-%x" (ade-agent-id agent)
          (truncate (* 1000000 (float-time))) (random most-positive-fixnum)))

(defun ade-send--invoke (function &rest args)
  "Invoke FUNCTION with ARGS, accepting one-argument callbacks too."
  (when function
    (condition-case err
        (apply function args)
      (wrong-number-of-arguments
       (condition-case _
           (funcall function (car args))
         (error (signal (car err) (cdr err))))))))

(defun ade-send-snapshot-match-p (agent snapshot)
  "Return non-nil when SNAPSHOT still describes AGENT's current send."
  (and (ade-agent-p agent)
       (ade-send-snapshot-p snapshot)
       (equal (ade-send-snapshot-agent-id snapshot) (ade-agent-id agent))
       (equal (ade-send-snapshot-thread-id snapshot)
              (ade-agent-thread-id agent))
       (equal snapshot (ade-agent-pending-send agent))))

(defun ade-send-accepted-callback
    (agent snapshot &optional callback result)
  "Clear AGENT's pending send only when SNAPSHOT still matches.

When CALLBACK is supplied it receives AGENT, SNAPSHOT, and RESULT (or just
the first argument when its arity is one).  This is the upper-layer contract
that prevents a late acceptance from clearing a newer send."
  (when (ade-send-snapshot-match-p agent snapshot)
    (ade-agent-clear-pending-send agent snapshot)
    (ade-send--invoke callback agent snapshot result)
    t))

(defun ade-send--assert-connection (agent)
  "Return AGENT's ready connection or signal."
  (let ((connection (and (ade-agent-p agent)
                         (ade-agent-connection agent))))
    (unless (and connection (ade-app-server-connected-p connection))
      (signal 'ade-send-not-allowed-error
              (list "Agent App Server connection is not ready" agent)))
    connection))

(defun ade-send-takeover (agent &optional confirmation)
  "Explicitly take over idle unknown-origin AGENT for ADE control.

AGENT must be the selected Agent of its current Workspace.  CONFIRMATION may
be a function receiving AGENT, or non-nil when an interactive caller has
already displayed the state and obtained an explicit confirmation.  No
takeover is performed for a detached, active, blocked, or unselected Agent;
reconnection never calls this function automatically."
  (let* ((workspace (and (ade-agent-workspace-uuid agent)
                         (ade-core-workspace-by-uuid
                          (ade-agent-workspace-uuid agent))))
         (selected (and workspace
                        (ade-workspace-selected-agent-id workspace)))
         (confirm (cond
                   ((functionp confirmation) confirmation)
                   (confirmation (lambda (_agent) t))
                   (ade-send-takeover-confirm-function
                    ade-send-takeover-confirm-function)
                   (t nil))))
    (unless (and workspace
                 (equal selected (ade-agent-id agent)))
      (signal 'ade-send-not-allowed-error
              (list "Only the selected Workspace Agent may be taken over"
                    agent)))
    (unless (eq (ade-agent-state agent) 'idle)
      (signal 'ade-send-not-allowed-error
              (list "Only an idle Agent may be taken over"
                    (ade-agent-state agent))))
    (cond
     ((eq (ade-agent-turn-origin agent) 'ade) t)
     ((not (eq (ade-agent-turn-origin agent) 'unknown)) nil)
     ((and confirm (funcall confirm agent))
      (ade-agent-set-turn-origin agent 'ade)
      t)
     (t nil))))

(defun ade-send--takeover-allowed-p (agent takeover)
  "Return whether unknown-origin AGENT may be explicitly taken over."
  (or (eq (ade-agent-turn-origin agent) 'ade)
      (and (eq (ade-agent-turn-origin agent) 'unknown)
           (ade-send-takeover agent takeover))))

(defun ade-send-turn (agent text &rest options)
  "Start an ADE-origin turn for AGENT with TEXT.

The optional OPTIONS may contain a callback function as the first argument,
`:takeover' to authorize an unknown-origin idle takeover, and `:model' or
`:effort' only when the caller explicitly wants a future-turn setting.  The
normal path leaves model selection inherited from the thread."
  (let* ((callback (and (functionp (car options)) (pop options)))
         (takeover (plist-get options :takeover))
         (model (plist-get options :model))
         (effort (plist-get options :effort))
         (connection (ade-send--assert-connection agent))
         (state (ade-agent-state agent))
         (origin (ade-agent-turn-origin agent)))
    (unless (eq state 'idle)
      (signal 'ade-send-not-allowed-error
              (list "Only an idle Agent can start a turn" state)))
    (unless (ade-send--takeover-allowed-p agent takeover)
      (signal 'ade-send-not-allowed-error
              (list "TUI/unknown-origin Agent is monitor-only" origin)))
    (let* ((client-id (ade-send--new-client-id agent))
           (snapshot
            (ade-send-snapshot--make
             :agent-id (ade-agent-id agent)
             :thread-id (ade-agent-thread-id agent)
             :turn-id nil
             :client-user-message-id client-id
             :generation (float-time)))
           (params (list (cons 'threadId (ade-agent-thread-id agent))
                         (cons 'input (ade-send--normalize-input text))
                         (cons 'clientUserMessageId client-id)
                         (cons 'turnTrigger "ade"))))
      (when model (setq params (append params (list (cons 'model model)))))
      (when effort (setq params (append params (list (cons 'effort effort)))))
      (ade-agent-set-pending-send agent snapshot)
      (ade-agent-remember-client-message agent client-id 'ade)
      (condition-case err
          (ade-app-server-call
           connection "turn/start" params
           (lambda (result)
             (let* ((turn (ade-send--json-get result 'turn))
                    (turn-id (ade-send--json-get turn 'id))
                    (accepted
                     (ade-send-snapshot--make
                      :agent-id (ade-send-snapshot-agent-id snapshot)
                      :thread-id (ade-send-snapshot-thread-id snapshot)
                      :turn-id turn-id
                      :client-user-message-id client-id
                      :generation (ade-send-snapshot-generation snapshot))))
               (ade-agent-set-pending-send agent accepted)
               (when turn-id
                 (ade-agent-set-current-turn-id agent turn-id)
                 (ade-agent-remember-turn-origin agent turn-id 'ade))
               (setf (ade-agent-state agent) 'working
                     (ade-agent-reason agent) 'turn-start-accepted)
               (ade-send--invoke callback agent accepted result)))
           (lambda (error)
             (ade-agent-clear-pending-send agent snapshot)
             (ade-send--invoke callback agent nil error)))
        (error
         (ade-agent-clear-pending-send agent snapshot)
         (signal (car err) (cdr err)))))))

(defun ade-send-steer
    (agent text &optional expected-turn-id callback errorback)
  "Steer AGENT's active turn with TEXT and EXPECTED-TURN-ID.

The expected id is sent as the protocol precondition; a stale id is rejected
locally before any wire mutation.  Steering is always ADE-origin only.
CALLBACK receives only a successful result; ERRORBACK receives only a protocol
failure.  The older four-argument form remains valid."
  (let* ((connection (ade-send--assert-connection agent))
         (current (ade-agent-current-turn-id agent))
         (expected (or expected-turn-id current)))
    (unless (and expected current (equal expected current))
      (signal 'ade-send-not-allowed-error
              (list "Expected active turn does not match" expected current)))
    (unless (ade-agent-control-allowed-p agent 'steer)
      (signal 'ade-send-not-allowed-error
              (list "Only ADE-origin active turns may be steered"
                    (ade-agent-turn-origin agent))))
    (let ((client-id (ade-send--new-client-id agent)))
      (ade-agent-remember-client-message agent client-id 'ade)
      (ade-app-server-call
       connection "turn/steer"
       (list (cons 'threadId (ade-agent-thread-id agent))
             (cons 'expectedTurnId expected)
             (cons 'input (ade-send--normalize-input text))
             (cons 'clientUserMessageId client-id))
       (lambda (result)
         (ade-send--invoke callback agent result))
       (lambda (error)
         (ade-send--invoke errorback agent error))))))

(defun ade-send-interrupt
    (agent &optional expected-turn-id callback)
  "Interrupt AGENT's active EXPECTED-TURN-ID explicitly."
  (let* ((connection (ade-send--assert-connection agent))
         (current (ade-agent-current-turn-id agent))
         (expected (or expected-turn-id current)))
    (unless (and expected current (equal expected current))
      (signal 'ade-send-not-allowed-error
              (list "Expected active turn does not match" expected current)))
    (unless (ade-agent-control-allowed-p agent 'interrupt)
      (signal 'ade-send-not-allowed-error
              (list "Only ADE-origin active turns may be interrupted"
                    (ade-agent-turn-origin agent))))
    (ade-app-server-call
     connection "turn/interrupt"
     (list (cons 'threadId (ade-agent-thread-id agent))
           (cons 'turnId expected))
     (lambda (result)
       (ade-send--invoke callback agent result))
     (lambda (error)
       (ade-send--invoke callback agent error)))))

(defalias 'ade-send-turn-start #'ade-send-turn)
(defalias 'ade-send-steer-turn #'ade-send-steer)
(defalias 'ade-send-stop #'ade-send-interrupt)

(provide 'ade-send)

;;; ade-send.el ends here
