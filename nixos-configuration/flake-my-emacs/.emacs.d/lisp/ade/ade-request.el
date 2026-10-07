;;; ade-request.el --- Explicit App Server request handling -*- lexical-binding: t; -*-

;;; Commentary:

;; App Server server requests are broadcast to every subscribed client.  ADE
;; therefore records them first and answers only after an explicit consult or
;; confirmation operation.  Ingress never opens a minibuffer or takes over a
;; TUI.  A request is answered at most once; the server's resolved event is
;; the authority that closes the local lifecycle.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ade-core)
(require 'ade-state)
(require 'ade-app-server)
(require 'ade-agent)

(defgroup ade-request nil
  "Explicit handling of Codex App Server server requests."
  :group 'ade)

(define-error 'ade-request-error "ADE server request error" 'ade-error)
(define-error 'ade-request-not-found-error
  "ADE server request was not found"
  'ade-request-error)
(define-error 'ade-request-already-resolved-error
  "ADE server request was already resolved"
  'ade-request-error)
(define-error 'ade-request-confirmation-required-error
  "ADE server request requires explicit cancellation confirmation"
  'ade-request-error)

(cl-defstruct (ade-request
               (:constructor ade-request--make))
  "An explicitly tracked App Server server request."
  id agent-id connection thread-id turn-id item-id kind method params
  choices status received-at response failure resolved-at)

(defvar ade-request--table (make-hash-table :test #'equal)
  "Tracked requests indexed by (connection . request-id).")

(defun ade-request-reset ()
  "Clear the in-memory request registry; intended for tests."
  (setq ade-request--table (make-hash-table :test #'equal))
  t)

(defun ade-request--key (connection request-id)
  "Return the table key for CONNECTION and REQUEST-ID."
  (cons connection request-id))

(defun ade-request--json-get (object key)
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

(defun ade-request--normalize-symbol (value)
  "Normalize protocol VALUE to a lowercase symbol."
  (cond
   ((symbolp value) value)
   ((stringp value) (intern (downcase value)))
   (t value)))

(defun ade-request--kind (method params)
  "Classify server METHOD and PARAMS into a stable request kind."
  (let ((method (downcase (format "%s" method))))
    (cond
     ((string-match-p
       (regexp-opt '("commandexecution/requestapproval"
                     "filechange/requestapproval"
                     "permissions/requestapproval"))
       method)
      'approval)
     ((string-match-p
       (regexp-opt '("requestuserinput" "elicitation/request"))
       method)
      'user-input)
     ((equal method "item/tool/call") 'tool-call)
     (t (or (ade-request--normalize-symbol
             (ade-request--json-get params 'kind))
            'unknown)))))

(defun ade-request--choice (value &optional label description metadata)
  "Build one structured choice plist."
  (list :value value
        :label (or label (format "%s" value))
        :description description
        :metadata metadata))

(defun ade-request--approval-choices (params)
  "Convert approval PARAMS into explicit structured choices."
  (mapcar
   (lambda (entry)
     (cond
      ((stringp entry) (ade-request--choice entry))
      ((symbolp entry) (ade-request--choice (symbol-name entry)))
      ((listp entry)
       (let ((key (or (car (car entry)) (car entry))))
         (ade-request--choice
          key
          (or (ade-request--json-get entry 'label) (format "%s" key))
          (ade-request--json-get entry 'description)
          entry)))
      (t (ade-request--choice entry))))
   (or (ade-request--json-get params 'availableDecisions)
       '())))

(defun ade-request--user-input-choices (params)
  "Convert user-input PARAMS questions into structured choices."
  (mapcar
   (lambda (question)
     (ade-request--choice
      (ade-request--json-get question 'id)
      (or (ade-request--json-get question 'header)
          (ade-request--json-get question 'question)
          "Input")
      (ade-request--json-get question 'question)
      question))
   (or (ade-request--json-get params 'questions) '())))

(defun ade-request--choices (kind params)
  "Build choices for KIND and PARAMS without invoking UI."
  (pcase kind
    ('approval (ade-request--approval-choices params))
    ('user-input (ade-request--user-input-choices params))
    (_ nil)))

(defun ade-request-by-id (request-id &optional connection)
  "Return REQUEST-ID, optionally constrained to CONNECTION."
  (if connection
      (gethash (ade-request--key connection request-id) ade-request--table)
    (let (found)
      (maphash (lambda (_key request)
                 (when (and (null found)
                            (equal request-id (ade-request-id request)))
                   (setq found request)))
               ade-request--table)
      found)))

(defun ade-request-pending-p (request)
  "Return non-nil when REQUEST is eligible for its first response.

`responding' remains outstanding for display, but is no longer sendable."
  (and (ade-request-p request)
       (eq (ade-request-status request) 'pending)))

(defun ade-request-outstanding-p (request)
  "Return non-nil when REQUEST awaits server resolution.

This includes a request whose response is already on the wire but for which
the authoritative `serverRequest/resolved' event has not arrived yet."
  (and (ade-request-p request)
       (memq (ade-request-status request) '(pending responding))))

(defun ade-request-pending-for-agent (agent)
  "Return pending requests belonging to AGENT."
  (let (requests)
    (maphash
     (lambda (_key request)
       (when (and (equal (ade-request-agent-id request)
                         (ade-agent-id agent))
                  (ade-request-outstanding-p request))
         (push request requests)))
     ade-request--table)
    (nreverse requests)))

(defun ade-request-ingest (agent connection message)
  "Record one server MESSAGE received for AGENT and CONNECTION.

This function is intentionally non-interactive.  It stores the pending
request and returns it; callers may later pass it to `ade-request-consult'."
  (let* ((id (ade-request--json-get message 'id))
         (params (ade-request--json-get message 'params))
         (method (ade-request--json-get message 'method))
         (key (ade-request--key connection id))
         (existing (gethash key ade-request--table)))
    (or existing
        (let* ((kind (ade-request--kind method params))
               (request
                (ade-request--make
                 :id id
                 :agent-id (ade-agent-id agent)
                 :connection connection
                 :thread-id (ade-request--json-get params 'threadId)
                 :turn-id (ade-request--json-get params 'turnId)
                 :item-id (ade-request--json-get params 'itemId)
                 :kind kind
                 :method method
                 :params params
                 :choices (ade-request--choices kind params)
                 :status 'pending
                 :received-at (float-time)
                 :response nil
                 :failure nil
                 :resolved-at nil)))
          (puthash key request ade-request--table)
          (setf (ade-agent-pending-requests agent)
                (cons id (delete id (ade-agent-pending-requests agent))))
          ;; A request is active evidence, but no UI is opened and no origin
          ;; is inferred from the request's transport connection.
          (when (fboundp 'ade-agent--apply-state-event)
            (ade-agent--apply-state-event
             agent (list :type 'server-request
                         :request-kind kind
                         :reason (if (eq kind 'approval)
                                     'waiting-on-approval
                                   'waiting-on-user-input)
                         :source 'app-server)))
          request))))

(defun ade-request--normalize-result (request decision)
  "Normalize DECISION into the App Server result object for REQUEST."
  (cond
   ((and (listp decision)
         (or (alist-get 'decision decision)
             (alist-get "decision" decision)
             (plist-member decision :decision)))
    decision)
   ((or (symbolp decision) (stringp decision))
    (list (cons 'decision (if (symbolp decision)
                              (symbol-name decision)
                            decision))))
   (t decision)))

(defun ade-request--drop-agent-pending (request)
  "Remove REQUEST id from its Agent's pending list when possible."
  (when-let* ((agent (and (fboundp 'ade-core-agent-by-id)
                          (ade-core-agent-by-id
                           (ade-request-agent-id request)))))
    (setf (ade-agent-pending-requests agent)
          (delete (ade-request-id request)
                  (ade-agent-pending-requests agent)))))

(defun ade-request-respond
    (request decision &optional on-success on-failure)
  "Explicitly answer REQUEST with DECISION.

The local status becomes `responding' before the wire send.  A transport send
failure rolls back to `pending'; only the server's resolved event establishes
`resolved'."
  (unless (ade-request-p request)
    (signal 'ade-request-not-found-error (list request)))
  (unless (and (ade-request-pending-p request)
               (eq (ade-request-status request) 'pending))
    (signal 'ade-request-already-resolved-error
            (list (ade-request-id request) (ade-request-status request))))
  (let ((result (ade-request--normalize-result request decision)))
    (setf (ade-request-status request) 'responding
          (ade-request-response request) result)
    (condition-case err
        (ade-app-server-respond-server-request
         (ade-request-connection request)
         (ade-request-id request)
         result
         (lambda (_record)
           (when on-success (funcall on-success request)))
         (lambda (_record failure)
           (setf (ade-request-status request) 'pending
                 (ade-request-failure request) failure)
           (when on-failure (funcall on-failure request failure))))
      (error
       (setf (ade-request-status request) 'pending
             (ade-request-failure request) err)
       (when on-failure (funcall on-failure request err))
       nil))))

(defun ade-request-resolved (agent request-id)
  "Mark AGENT REQUEST-ID resolved after server confirmation.

Repeated resolved events are harmless.  A resolved event never causes another
response and never opens/changes a terminal UI."
  (let* ((connection (ade-agent-connection agent))
         (request (or (ade-request-by-id request-id connection)
                      (ade-request-by-id request-id))))
    (when request
      (unless (eq (ade-request-status request) 'resolved)
        (setf (ade-request-status request) 'resolved
              (ade-request-resolved-at request) (float-time)))
      (ade-request--drop-agent-pending request)
      request)))

(defun ade-request-failed (request error)
  "Roll REQUEST back to pending after a response FAILURE."
  (when (ade-request-p request)
    (setf (ade-request-status request) 'pending
          (ade-request-failure request) error)
    request))

(defun ade-request-consult (request &optional chooser)
  "Return structured choices or invoke explicit CHOOSER for REQUEST.

When CHOOSER is nil this function only returns choices.  A `quit' (C-g)
returns nil and does not answer or cancel the request."
  (unless (ade-request-p request)
    (signal 'ade-request-not-found-error (list request)))
  (condition-case _quit
      (if chooser
          (funcall chooser (ade-request-choices request) request)
        (ade-request-choices request))
    (quit nil)))

(defun ade-request-confirm-cancel (request &optional confirmer)
  "Ask CONFIRMER for explicit cancellation of REQUEST.

The default is `yes-or-no-p' only in an interactive context.  C-g leaves the
request pending and sends no response."
  (let ((confirm (or confirmer
                    (and (called-interactively-p 'interactive)
                         (lambda (_request)
                           (yes-or-no-p "Cancel this Codex request? "))))))
    (unless confirm
      (signal 'ade-request-confirmation-required-error
              (list (ade-request-id request))))
    (condition-case _quit
        (funcall confirm request)
      (quit nil))))

(defun ade-request-cancel (request &optional confirmer on-failure)
  "Cancel REQUEST only after explicit CONFIRMER approval.

Without confirmation, no wire response is emitted.  This is the safe path
for C-g and for monitor-only TUI/unknown requests."
  (when (and (ade-request-p request)
             (ade-request-confirm-cancel request confirmer))
    (ade-request-respond request "cancel" nil on-failure)))

(defalias 'ade-request-cancel-confirmed #'ade-request-cancel)

(provide 'ade-request)

;;; ade-request.el ends here
