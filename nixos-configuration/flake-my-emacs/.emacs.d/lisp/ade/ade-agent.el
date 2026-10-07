;;; ade-agent.el --- App Server-backed ADE Agent lifecycle -*- lexical-binding: t; -*-

;;; Commentary:

;; An Agent is the only ADE object that owns a Codex App Server connection.
;; The connection is therefore also the event-reader boundary.  This file
;; deliberately contains no display, window, Perspective, or Prompt code.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ade-core)
(require 'ade-state)
(require 'ade-app-server)

(defgroup ade-agent nil
  "Codex Agent lifecycle and App Server reconciliation."
  :group 'ade)

(defcustom ade-agent-default-url ade-app-server-default-url
  "Default App Server URL for newly created Agents."
  :type 'string
  :group 'ade-agent)

(define-error 'ade-agent-error "ADE Agent error" 'ade-error)
(define-error 'ade-agent-not-ready-error
  "ADE Agent is not ready for the requested operation"
  'ade-agent-error)
(define-error 'ade-agent-origin-error
  "ADE Agent turn origin does not permit this operation"
  'ade-agent-error)

(defun ade-agent--json-get (object key)
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

(defun ade-agent--normalize-symbol (value)
  "Normalize a protocol string or symbol VALUE to a lowercase symbol."
  (cond
   ((symbolp value) value)
   ((stringp value) (intern (downcase value)))
   (t value)))

(defun ade-agent--new-id (&optional prefix)
  "Return a process-local stable id with optional PREFIX."
  (let* ((seed (format "%s:%s:%s:%s"
                       (float-time) (emacs-pid) (random) (user-uid)))
         (digest (md5 seed)))
    (format "%s-%s-%s" (or prefix "agent") digest (substring digest 0 8))))

(defun ade-agent--metadata-get (agent key)
  "Return KEY from AGENT metadata."
  (plist-get (ade-agent-metadata agent) key))

(defun ade-agent--metadata-put (agent key value)
  "Set KEY to VALUE in AGENT metadata and return VALUE."
  (setf (ade-agent-metadata agent)
        (plist-put (or (ade-agent-metadata agent) '()) key value))
  value)

(defun ade-agent--invoke (function &rest arguments)
  "Invoke FUNCTION with ARGUMENTS, accepting one-argument callbacks too."
  (when function
    (condition-case err
        (apply function arguments)
      (wrong-number-of-arguments
       (condition-case _
           (funcall function (car arguments))
         (error (signal (car err) (cdr err))))))))

(defun ade-agent--ensure-tables (agent)
  "Ensure AGENT metadata has its correlation tables."
  (dolist (entry '((:turn-origins . equal)
                   (:ade-client-ids . equal)
                   (:request-ids . equal)))
    (let ((key (car entry)))
      (unless (hash-table-p (ade-agent--metadata-get agent key))
        (ade-agent--metadata-put
         agent key (make-hash-table :test (cdr entry))))))
  agent)

(defun ade-agent-new (&rest options)
  "Create an unregistered ADE Agent from keyword OPTIONS.

Important options are `:id', `:workspace-uuid', `:thread-id', `:session-id',
`:endpoint', `:root', `:model', `:effort', `:source', and `:metadata'.  The
record is inert until `ade-agent-connect' and, where appropriate,
`ade-agent-register-after-handshake' are called."
  (let* ((id (or (plist-get options :id) (ade-agent--new-id)))
         (metadata (copy-sequence (or (plist-get options :metadata) '())))
         (agent
          (ade-agent-create
           :id id
           :workspace-uuid (plist-get options :workspace-uuid)
           :thread-id (plist-get options :thread-id)
           :session-id (plist-get options :session-id)
           :main-thread-id (or (plist-get options :main-thread-id)
                               (plist-get options :thread-id))
           :side-thread-id nil
           :buffer (plist-get options :buffer)
           :process (plist-get options :process)
           :connection nil
           :state (or (plist-get options :state) 'unknown)
           :reason (or (plist-get options :reason) 'not-connected)
           :source (or (plist-get options :source) 'app-server)
           :observed-at (float-time)
           :latest-event nil
           :unread-p nil
           :pending-requests nil
           :turn-origin 'unknown
           :lifecycle 'created
           :model (plist-get options :model)
           :effort (plist-get options :effort)
           :detached-p nil
           :metadata metadata)))
    (ade-agent--metadata-put agent :endpoint
                             (or (plist-get options :endpoint)
                                 ade-agent-default-url))
    (ade-agent--metadata-put agent :root (plist-get options :root))
    (ade-agent--metadata-put agent :current-turn-id nil)
    (ade-agent--metadata-put agent :pending-send nil)
    (ade-agent--metadata-put agent :handshake-p nil)
    (ade-agent--ensure-tables agent)
    agent))

(defalias 'ade-agent-create-record #'ade-agent-new)

(defun ade-agent-current-turn-id (agent)
  "Return AGENT's currently active turn id, or nil."
  (ade-agent--metadata-get agent :current-turn-id))

(defun ade-agent-set-current-turn-id (agent turn-id)
  "Set AGENT's current turn id to TURN-ID and return TURN-ID."
  (ade-agent--metadata-put agent :current-turn-id turn-id))

(defun ade-agent-set-turn-origin (agent origin)
  "Set AGENT's current turn ORIGIN and return ORIGIN.

Only `ade', `tui', and `unknown' are accepted.  An origin is never inferred
from a terminal buffer or from the App Server connection's source label."
  (let ((origin (ade-agent--normalize-symbol origin)))
    (unless (memq origin ade-turn-origins)
      (signal 'ade-agent-origin-error (list "Unknown turn origin" origin)))
    (setf (ade-agent-turn-origin agent) origin)
    origin))

(defun ade-agent-remember-turn-origin (agent turn-id origin)
  "Remember ORIGIN for TURN-ID on AGENT."
  (ade-agent--ensure-tables agent)
  (puthash turn-id (ade-agent--normalize-symbol origin)
           (ade-agent--metadata-get agent :turn-origins))
  (ade-agent-set-turn-origin agent origin))

(defun ade-agent-remember-client-message (agent client-id origin)
  "Remember CLIENT-ID as an ORIGIN marker for AGENT."
  (when (and client-id (stringp client-id))
    (ade-agent--ensure-tables agent)
    (puthash client-id (ade-agent--normalize-symbol origin)
             (ade-agent--metadata-get agent :ade-client-ids)))
  client-id)

(defun ade-agent-origin-for-turn (agent turn-id)
  "Return remembered origin for TURN-ID, defaulting to `unknown'."
  (or (gethash turn-id (ade-agent--metadata-get agent :turn-origins))
      'unknown))

(defun ade-agent-origin-for-client-message (agent client-id)
  "Return remembered origin for CLIENT-ID, defaulting to `unknown'."
  (or (and client-id
           (gethash client-id (ade-agent--metadata-get agent :ade-client-ids)))
      'unknown))

(defun ade-agent-control-allowed-p (agent operation)
  "Return whether OPERATION is allowed for AGENT's current origin/state."
  (and (ade-agent-p agent)
       (ade-state-control-allowed-p
        (list :canonical (ade-agent-state agent)
              :turn-origin (ade-agent-turn-origin agent))
        operation)))

(defun ade-agent--apply-state-event (agent event)
  "Apply normalized EVENT to AGENT, tolerating missing optional state code."
  (if (fboundp 'ade-state-apply-event)
      (ade-state-apply-event agent event)
    (setf (ade-agent-state agent) 'unknown
          (ade-agent-reason agent) 'state-reducer-unavailable)
    agent))

(defun ade-agent--set-model-from (agent object)
  "Update AGENT model/effort from protocol OBJECT when available."
  (let* ((thread (ade-agent--json-get object 'thread))
         (settings (ade-agent--json-get object 'threadSettings))
         (model (or (ade-agent--json-get object 'model)
                    (ade-agent--json-get thread 'model)
                    (ade-agent--json-get settings 'model)))
         (effort (or (ade-agent--json-get object 'reasoningEffort)
                     (ade-agent--json-get object 'effort)
                     (ade-agent--json-get thread 'reasoningEffort)
                     (ade-agent--json-get settings 'effort))))
    (when model (setf (ade-agent-model agent) model))
    (when effort (setf (ade-agent-effort agent) effort))
    agent))

(defun ade-agent--set-thread-from (agent object)
  "Update identity/settings fields on AGENT from resume/start OBJECT."
  (let* ((thread (or (ade-agent--json-get object 'thread) object))
         (thread-id (ade-agent--json-get thread 'id))
         (session-id (ade-agent--json-get thread 'sessionId)))
    (when thread-id
      (setf (ade-agent-thread-id agent) thread-id)
      (unless (ade-agent-main-thread-id agent)
        (setf (ade-agent-main-thread-id agent) thread-id)))
    (when session-id (setf (ade-agent-session-id agent) session-id))
    (ade-agent--set-model-from agent object)
    (let* ((status (ade-agent--json-get thread 'status))
           (status-type (ade-agent--normalize-symbol
                         (or (ade-agent--json-get status 'type) status)))
           (flags (ade-agent--json-get status 'activeFlags)))
      (when status
        (ade-agent--apply-state-event
         agent (list :type 'thread-status :status status-type
                     :active-flags flags :source 'app-server))))
    (when (ade-agent-p (ade-core-agent-by-id (ade-agent-id agent)))
      (ignore-errors (ade-core-update-agent agent)))
    agent))

(defun ade-agent--resume-error-unsupported-p (error-object)
  "Return non-nil when ERROR-OBJECT indicates an unsupported method."
  (let ((code (ade-agent--json-get error-object 'code))
        (message (format "%s" (or (ade-agent--json-get error-object 'message)
                                   error-object))))
    (or (equal code -32601)
        (string-match-p
         (regexp-opt '("unsupported" "method not found" "not found"))
         (downcase message)))))

(defun ade-agent-register-after-handshake (agent &optional select-p)
  "Register AGENT only after its App Server handshake succeeds.

The Agent's Workspace UUID must already be present.  SELECT-P is explicit;
normal reconnect/adoption keeps the Workspace's existing selection."
  (unless (and (ade-agent-p agent)
               (ade-agent-connection agent)
               (ade-app-server-connected-p (ade-agent-connection agent)))
    (signal 'ade-agent-not-ready-error
            (list "App Server handshake has not completed" agent)))
  (unless (ade-agent-workspace-uuid agent)
    (signal 'ade-agent-not-ready-error
            (list "Agent has no Workspace UUID" agent)))
  (let ((existing (ade-core-agent-by-id (ade-agent-id agent))))
    (if existing
        (ade-core-update-agent agent)
      (ade-core-register-agent agent select-p)))
  (ade-agent--metadata-put agent :handshake-p t)
  agent)

(defun ade-agent--on-connected (agent _connection &optional reconnected)
  "Handle a successful initial or reconnect handshake for AGENT."
  (ade-agent--metadata-put agent :handshake-p t)
  ;; A reconnect does not restore turn ownership.  The resumed status and
  ;; subsequent clientUserMessageId correlation must establish it again.
  (ade-agent-set-turn-origin agent 'unknown)
  (ade-agent--apply-state-event
   agent (list :type (if reconnected 'connection-restored
                       'connection-restored)
               :source 'app-server))
  ;; Reconciliation is the only automatic operation after reconnect.  It
  ;; never re-sends a prompt or changes Workspace selection.
  (if (ade-agent-thread-id agent)
      (ade-agent-resume
       agent
       (lambda (_agent _result)
         (when-let* ((callback (ade-agent--metadata-get agent :on-ready)))
           (ade-app-server--invoke callback agent)))
       (lambda (_agent _error)
         ;; Unsupported history/list methods are a safe unknown state; no
         ;; mutation is attempted after a failed reconcile.
         (ade-agent--apply-state-event
          agent (list :type 'connection-restored :source 'app-server))
         (when-let* ((callback (ade-agent--metadata-get agent :on-ready)))
           (ade-app-server--invoke callback agent))))
    (when-let* ((callback (ade-agent--metadata-get agent :on-ready)))
      (ade-app-server--invoke callback agent)))
  agent)

(defun ade-agent--on-disconnected (agent _connection reason)
  "Mark AGENT unknown after a disconnect without deleting its record."
  (ade-agent--metadata-put agent :handshake-p nil)
  (ade-agent-set-turn-origin agent 'unknown)
  (ade-agent--apply-state-event
   agent (list :type 'connection-lost :reason reason :source 'app-server))
  agent)

(defun ade-agent--on-protocol-error (agent _connection error)
  "Record a protocol ERROR on AGENT without taking over any UI."
  (setf (ade-agent-reason agent) error
        (ade-agent-state agent) 'unknown
        (ade-agent-lifecycle agent) 'protocol-error)
  agent)

(defun ade-agent--on-server-request (agent connection record message)
  "Pass a server request to the request layer without opening a UI."
  (ignore record)
  (when (fboundp 'ade-request-ingest)
    (ade-request-ingest agent connection message)))

(defun ade-agent--on-event (agent _connection message)
  "Reduce one raw App Server MESSAGE into AGENT state/correlation metadata."
  (let* ((method (ade-agent--normalize-symbol
                  (ade-agent--json-get message 'method)))
         (params (ade-agent--json-get message 'params))
         (thread-id (ade-agent--json-get params 'threadId))
         (event-source 'app-server))
    (when (or (null thread-id)
              (equal thread-id (ade-agent-thread-id agent))
              (equal thread-id (ade-agent-side-thread-id agent)))
      (pcase method
        ('thread/status/changed
         (let* ((status (ade-agent--json-get params 'status))
                (status-type (ade-agent--normalize-symbol
                              (or (ade-agent--json-get status 'type)
                                  status)))
                (active-flags (ade-agent--json-get status 'activeFlags)))
           (ade-agent--apply-state-event
            agent (list :type 'thread-status
                        :status status-type
                        :active-flags active-flags
                        :source event-source))))
        ('turn/started
         (let* ((turn (ade-agent--json-get params 'turn))
                (turn-id (ade-agent--json-get turn 'id))
                (origin (ade-agent-origin-for-turn agent turn-id)))
           (ade-agent-set-current-turn-id agent turn-id)
           (ade-agent-set-turn-origin agent origin)
           (ade-agent--apply-state-event
            agent (list :type 'turn-started :source event-source))))
        ((or 'item/started 'item/completed)
         (let ((item (ade-agent--json-get params 'item)))
           (when (equal (ade-agent--normalize-symbol
                        (ade-agent--json-get item 'type))
                        'usermessage)
             ;; A null/unknown client id is deliberately unknown; the
             ;; App Server does not identify which connected client sent it.
             (ade-agent-set-turn-origin
              agent (ade-agent-origin-for-client-message
                     agent (ade-agent--json-get item 'clientId))))))
        ('turn/completed
         (ade-agent--apply-state-event
          agent (list :type 'turn-completed
                      :reason (ade-agent--json-get
                               (ade-agent--json-get params 'turn) 'status)
                      :source event-source))
         (ade-agent-set-current-turn-id agent nil)
         ;; Keep ADE ownership across the completed->idle transition.  A new
         ;; turn/started event replaces it with the remembered ADE id or with
         ;; `unknown' when the event has no ADE client correlation.
         )
        ('thread/settings/updated
         (ade-agent--set-model-from agent
                                    (ade-agent--json-get params
                                                         'threadSettings)))
        ('serverrequest/resolved
         (when (fboundp 'ade-request-resolved)
           (ade-request-resolved agent
                                 (ade-agent--json-get params 'requestId))))
        ('thread/started
         (ade-agent--set-thread-from agent
                                     (ade-agent--json-get params 'thread)))
        (_ nil)))
    ;; Always retain the raw message for diagnostics, never parse terminal
    ;; prose as a state signal.
    (setf (ade-agent-latest-event agent) message
          (ade-agent-observed-at agent) (float-time))
    agent))

(defun ade-agent-connect (agent &optional on-ready)
  "Connect AGENT to its per-Agent App Server reader.

ON-READY is invoked only after initialize/initialized and, when a thread id
exists, after the safe `thread/resume' reconciliation."
  (unless (ade-agent-p agent)
    (signal 'ade-agent-error (list "Not an ADE Agent" agent)))
  (when on-ready (ade-agent--metadata-put agent :on-ready on-ready))
  (let ((connection
         (or (ade-agent-connection agent)
             (setf (ade-agent-connection agent)
                   (ade-app-server-create
                    :url (ade-agent--metadata-get agent :endpoint)
                    :on-event (lambda (conn message)
                                (ignore conn)
                                (ade-agent--on-event agent conn message))
                    :on-request (lambda (conn record message)
                                  (ade-agent--on-server-request
                                   agent conn record message))
                    :on-connected (lambda (conn)
                                   (ade-agent--on-connected agent conn nil))
                    :on-reconnected (lambda (conn)
                                      (ade-agent--on-connected agent conn t))
                    :on-disconnected (lambda (conn reason)
                                       (ade-agent--on-disconnected
                                        agent conn reason))
                    :on-protocol-error (lambda (conn error)
                                         (ade-agent--on-protocol-error
                                          agent conn error)))))))
    (ade-app-server-connect connection)
    agent))

(defun ade-agent-disconnect (agent &optional intentional)
  "Disconnect AGENT's App Server reader while retaining its record."
  (if-let* ((connection (ade-agent-connection agent)))
      ;; The App Server callback owns the single disconnect transition.  Do
      ;; not apply it a second time here, which would duplicate state-hook
      ;; notifications and obscure the actual close reason.
      (ade-app-server-disconnect connection intentional)
    (unless intentional
      (ade-agent--on-disconnected agent nil 'closed)))
  agent)

(defun ade-agent-resume
    (agent &optional callback errorback)
  "Resume AGENT's thread and reconcile status/history metadata.

Only thread metadata is requested automatically (`excludeTurns t`).  History
is explicit through `thread/turns/list' and `thread/items/list' so a reconnect
never replays a prompt."
  (let ((connection (ade-agent-connection agent))
        (thread-id (ade-agent-thread-id agent)))
    (unless (and connection (ade-app-server-connected-p connection))
      (signal 'ade-agent-not-ready-error (list "Agent is not connected")))
    (unless thread-id
      (signal 'ade-agent-error (list "Agent has no thread id")))
    (ade-app-server-call
     connection "thread/resume"
     (list (cons 'threadId thread-id)
           (cons 'excludeTurns t))
     (lambda (result)
       (ade-agent--set-thread-from agent result)
       (ade-agent-set-turn-origin agent 'unknown)
       (ade-agent--invoke callback agent result))
     (lambda (error)
       ;; In particular, -32601/unsupported history leaves the Agent
       ;; unknown.  No fallback may issue a mutation or replay a turn.
       (when (ade-agent--resume-error-unsupported-p error)
         (ade-agent--apply-state-event
          agent (list :type 'connection-restored :source 'app-server)))
       (ade-agent--invoke errorback agent error)))))

(defalias 'ade-agent-reconcile #'ade-agent-resume)

(defun ade-agent-thread-start
    (agent &optional params callback errorback)
  "Start an App Server thread for AGENT with PARAMS.

The caller must explicitly register the resulting Agent after the connection
handshake; this function never changes Workspace selection."
  (let ((connection (ade-agent-connection agent)))
    (unless (and connection (ade-app-server-connected-p connection))
      (signal 'ade-agent-not-ready-error (list "Agent is not connected")))
    (ade-app-server-call
     connection "thread/start"
     (or params
         (list (cons 'cwd (ade-agent--metadata-get agent :root))))
     (lambda (result)
       (ade-agent--set-thread-from agent result)
       (ade-agent-set-turn-origin agent 'unknown)
       (ade-agent--invoke callback agent result))
     (lambda (error)
       (ade-agent--invoke errorback agent error)))))

(defalias 'ade-agent-start-thread #'ade-agent-thread-start)

(defun ade-agent-mark-process (agent process buffer)
  "Attach PROCESS and BUFFER metadata to AGENT without changing selection."
  (setf (ade-agent-process agent) process
        (ade-agent-buffer agent) buffer)
  agent)

(defun ade-agent-process-exited (agent &optional status)
  "Record a non-destructive PROCESS exit for AGENT."
  (setf (ade-agent-process agent) nil)
  (ade-agent--apply-state-event
   agent (list :type 'process-exited :reason status :source 'ghostel))
  agent)

(defun ade-agent-set-pending-send (agent snapshot)
  "Set AGENT's pending accepted-send SNAPSHOT."
  (ade-agent--metadata-put agent :pending-send snapshot))

(defun ade-agent-pending-send (agent)
  "Return AGENT's pending send snapshot, if any."
  (ade-agent--metadata-get agent :pending-send))

(defun ade-agent-clear-pending-send (agent &optional snapshot)
  "Clear AGENT pending send when SNAPSHOT still matches, and return t."
  (when (or (null snapshot)
            (equal snapshot (ade-agent-pending-send agent)))
    (ade-agent--metadata-put agent :pending-send nil)
    t))

(defun ade-agent-detach (agent)
  "Detach AGENT without killing process/buffer or deleting its record."
  (when (ade-agent-p (ade-core-agent-by-id (ade-agent-id agent)))
    (ade-core-detach-agent (ade-agent-id agent)))
  (setf (ade-agent-detached-p agent) t)
  (ade-agent-disconnect agent t)
  agent)

(defun ade-agent-reattach (agent workspace-uuid &optional connect-p select-p)
  "Reattach AGENT to WORKSPACE-UUID, unselected unless SELECT-P is non-nil."
  (ade-core-attach-agent (ade-agent-id agent) workspace-uuid select-p)
  (setf (ade-agent-workspace-uuid agent) workspace-uuid
        (ade-agent-detached-p agent) nil)
  (when connect-p (ade-agent-connect agent))
  agent)

(provide 'ade-agent)

;;; ade-agent.el ends here
