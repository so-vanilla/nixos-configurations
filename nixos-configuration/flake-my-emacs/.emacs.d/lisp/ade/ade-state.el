;;; ade-state.el --- Canonical ADE state reducer -*- lexical-binding: t; -*-

;;; Commentary:

;; State conversion is kept independent from transport and UI.  App Server
;; adapters can feed normalized event plists to `ade-state-reduce', while ERT
;; tests can exercise every transition without opening a window or starting a
;; process.

;;; Code:

(require 'cl-lib)
(require 'ade-core)

(defgroup ade-state nil
  "Canonical ADE state conversion."
  :group 'ade)

(defvar ade-state-change-hook nil
  "Hook run after `ade-state-apply-event' changes an Agent record.

Functions on this hook must not open a minibuffer, select a window, or change
the current Workspace."
  )

(defun ade-state--event-value (event key)
  "Return KEY from EVENT, accepting keyword and string keys."
  (or (plist-get event key)
      (when (stringp (plist-get event :type))
        (plist-get event (intern (concat ":" (plist-get event :type)))))))

(defun ade-state--normalize-symbol (value)
  "Normalize a symbol/string VALUE to a lowercase symbol."
  (cond
   ((symbolp value) (intern (downcase (symbol-name value))))
   ((stringp value) (intern (downcase value)))
   (t value)))

(defun ade-state--normalize-list (value)
  "Normalize a list of symbols/strings VALUE."
  (mapcar #'ade-state--normalize-symbol (or value nil)))

(defun ade-state--metadata (state canonical reason source event lifecycle)
  "Build a normalized state plist from the supplied values."
  (list :canonical canonical
        :reason reason
        :source source
        :observed-at (or (plist-get event :observed-at) (float-time))
        :latest-event event
        :unread (if (and (listp state) (plist-member state :unread))
                    (plist-get state :unread)
                  nil)
        :turn-origin (or (plist-get event :turn-origin)
                         (plist-get event :origin)
                         (and (listp state) (plist-get state :turn-origin))
                         'unknown)
        :lifecycle (or lifecycle
                        (and (listp state)
                             (plist-get state :lifecycle)))))

(defun ade-state-thread-status (status &optional active-flags)
  "Convert an App Server STATUS and ACTIVE-FLAGS to canonical state metadata.

STATUS may be a symbol, string, or plist such as `(:type active)'.  Waiting
flags take precedence over an otherwise active status.  The return value is a
plist containing `:canonical' and `:reason'."
  (let* ((type (if (listp status)
                   (plist-get status :type)
                 status))
         (type (ade-state--normalize-symbol type))
         (flags (ade-state--normalize-list
                 (or active-flags
                     (and (listp status)
                          (plist-get status :active-flags))))))
    (cond
     ((memq 'waitingonapproval flags)
      (list :canonical 'blocked :reason 'waiting-on-approval))
     ((memq 'waitingonuserinput flags)
      (list :canonical 'blocked :reason 'waiting-on-user-input))
     ((eq type 'active)
      (list :canonical 'working :reason 'active))
     ((eq type 'idle)
      (list :canonical 'idle :reason 'idle))
     ((eq type 'systemerror)
      (list :canonical 'unknown :reason 'system-error))
     ((eq type 'notloaded)
      (list :canonical 'unknown :reason 'not-loaded))
     (t
      (list :canonical 'unknown :reason 'unrecognized-status)))))

(defun ade-state--event-transition (state event)
  "Return the pure next state plist for EVENT applied to STATE."
  (let* ((type (ade-state--normalize-symbol (plist-get event :type)))
         (source (or (plist-get event :source) 'app-server))
         (status-result nil)
         (canonical nil)
         (reason nil)
         (lifecycle nil))
    (pcase type
      ((or 'thread-status 'status)
       (setq status-result
             (ade-state-thread-status (plist-get event :status)
                                      (plist-get event :active-flags)))
       (setq canonical (plist-get status-result :canonical)
             reason (plist-get status-result :reason)
             lifecycle 'running))
      ('turn-started
       (setq canonical 'working
             reason 'turn-started
             lifecycle 'running))
      ('turn-completed
       ;; Only an explicit lifecycle event can establish `done'.
       (setq canonical 'done
             reason (or (plist-get event :reason) 'turn-completed)
             lifecycle 'completed))
      ('turn-failed
       (setq canonical 'unknown
             reason (or (plist-get event :reason) 'turn-failed)
             lifecycle 'failed))
      ('process-exited
       ;; Process exit is metadata, not proof of completion.
       (setq canonical 'unknown
             reason 'process-exited
             lifecycle 'exited))
      ('connection-lost
       (setq canonical 'unknown
             reason 'connection-lost
             lifecycle 'disconnected))
      ('connection-restored
       ;; Restoration alone does not infer a live state; the subsequent
       ;; authoritative thread/status event supplies it.
       (setq canonical 'unknown
             reason 'awaiting-reconciliation
             lifecycle 'reconnecting))
      ('server-request
       (setq canonical 'blocked
             reason (or (plist-get event :reason)
                        (if (eq (plist-get event :request-kind) 'approval)
                            'waiting-on-approval
                          'waiting-on-user-input))
             lifecycle 'waiting))
      ('explicit-report
       (setq canonical (ade-state--normalize-symbol
                        (plist-get event :canonical))
             reason (plist-get event :reason)
             lifecycle (plist-get event :lifecycle))
       (unless (memq canonical ade-canonical-states)
         (setq canonical 'unknown
               reason 'invalid-explicit-report)))
      (_
       (setq canonical 'unknown
             reason 'unrecognized-event
             lifecycle (or (plist-get state :lifecycle) 'unknown))))
    (ade-state--metadata state canonical reason source event lifecycle)))

(defun ade-state-reduce (state event)
  "Return the next normalized state after applying EVENT to STATE.

STATE is a plist with `:canonical', `:reason', `:source', `:observed-at',
`:latest-event', `:unread', `:turn-origin', and `:lifecycle'.  EVENT is a
normalized event plist.  The function is pure with respect to both arguments."
  (let ((state (cond
                ((listp state) state)
                ((null state) '(:canonical unknown :turn-origin unknown))
                (t (list :canonical (ade-state--normalize-symbol state)
                         :turn-origin 'unknown)))))
    (ade-state--event-transition state (or event '(:type unknown)))))

(defun ade-state-set-turn-origin (state origin)
  "Return STATE with ORIGIN normalized to `ade', `tui', or `unknown'."
  (let ((origin (ade-state--normalize-symbol origin)))
    (unless (memq origin ade-turn-origins)
      (signal 'ade-invariant-error (list "Unknown turn origin" origin)))
    (plist-put (copy-sequence state) :turn-origin origin)))

(defun ade-state-control-allowed-p (state operation)
  "Return non-nil when STATE permits ADE OPERATION.

Idle Agents may start a turn.  Active ADE-origin Agents may steer or
interrupt.  TUI/unknown origins are monitor-only.  Blocked requests must be
answered through the request protocol, not normal Prompt sending."
  (let ((canonical (plist-get state :canonical))
        (origin (or (plist-get state :turn-origin) 'unknown)))
    (pcase operation
      ('start (and (eq canonical 'idle) (eq origin 'ade)))
      ((or 'steer 'interrupt)
       (and (eq canonical 'working) (eq origin 'ade)))
      ('respond (eq canonical 'blocked))
      (_ nil))))

(defun ade-state-apply-event (agent event)
  "Apply EVENT to ADE AGENT and run the state-change hook.

The event hook is observational.  It must not perform UI takeover.  Return
the updated Agent record."
  (unless (ade-agent-p agent)
    (signal 'ade-invariant-error (list "Not an ADE Agent" agent)))
  (let* ((old-state (list :canonical (ade-state--canonical-of agent)
                          :reason (ade-agent-reason agent)
                          :source (ade-agent-source agent)
                          :observed-at (ade-agent-observed-at agent)
                          :latest-event (ade-agent-latest-event agent)
                          :unread (ade-agent-unread-p agent)
                          :turn-origin (or (ade-agent-turn-origin agent)
                                           'unknown)
                          :lifecycle (ade-agent-lifecycle agent)))
         (new-state (ade-state-reduce old-state event)))
    (setf (ade-agent-state agent) (plist-get new-state :canonical)
          (ade-agent-reason agent) (plist-get new-state :reason)
          (ade-agent-source agent) (plist-get new-state :source)
          (ade-agent-observed-at agent) (plist-get new-state :observed-at)
          (ade-agent-latest-event agent) (plist-get new-state :latest-event)
          (ade-agent-unread-p agent) (plist-get new-state :unread)
          (ade-agent-turn-origin agent) (plist-get new-state :turn-origin)
          (ade-agent-lifecycle agent) (plist-get new-state :lifecycle))
    (run-hook-with-args 'ade-state-change-hook agent event)
    agent))

(defun ade-state--canonical-of (value)
  "Extract a canonical state symbol from VALUE."
  (let ((canonical (if (ade-agent-p value)
                       (ade-agent-state value)
                     (plist-get value :canonical))))
    (ade-state--normalize-symbol canonical)))

(defun ade-state-rollup (agents)
  "Return the canonical Workspace state for AGENTS.

An empty list returns `no-agent'.  Active evidence has precedence over
uncertainty: `blocked' > `working'.  If there is no active evidence and any
Agent is `unknown', the aggregate remains `unknown' rather than falsely
claiming `done' or `idle'."
  (if (null agents)
      'no-agent
    (let ((states (mapcar #'ade-state--canonical-of agents)))
      (cond
       ((memq 'blocked states) 'blocked)
       ((memq 'working states) 'working)
       ((memq 'unknown states) 'unknown)
       ((memq 'done states) 'done)
       ((memq 'idle states) 'idle)
       (t 'unknown)))))

(provide 'ade-state)

;;; ade-state.el ends here
