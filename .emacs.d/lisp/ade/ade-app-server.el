;;; ade-app-server.el --- JSON-RPC App Server transport for ADE -*- lexical-binding: t; -*-

;;; Commentary:

;; This is the deliberately small transport boundary between ADE and Codex's
;; App Server.  A connection is owned by one Agent and has one persistent
;; event reader.  The wire format is plain JSON-RPC over websocket text
;; frames; no Content-Length/header envelope is added.
;;
;; The transport factory is injectable.  Tests use a fake websocket without
;; opening a socket, while the normal factory delegates to websocket.el.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(defgroup ade-app-server nil
  "Codex App Server transport used by ADE."
  :group 'ade)

(defcustom ade-app-server-default-url "ws://127.0.0.1:47321"
  "Default localhost App Server websocket URL."
  :type 'string
  :group 'ade-app-server)

(defcustom ade-app-server-client-name "ade-emacs"
  "Client name sent in the App Server initialize handshake."
  :type 'string
  :group 'ade-app-server)

(defcustom ade-app-server-client-version "0.1.0"
  "Client version sent in the App Server initialize handshake."
  :type 'string
  :group 'ade-app-server)

(defcustom ade-app-server-reconnect-base-delay 1.0
  "Initial delay in seconds before an unexpected reconnect."
  :type 'number
  :group 'ade-app-server)

(defcustom ade-app-server-reconnect-max-delay 30.0
  "Maximum delay in seconds between reconnect attempts."
  :type 'number
  :group 'ade-app-server)

(defcustom ade-app-server-reconnect-max-attempts nil
  "Maximum automatic reconnect attempts, or nil for no finite limit."
  :type '(choice (const :tag "Unlimited" nil) integer)
  :group 'ade-app-server)

(define-error 'ade-app-server-error "ADE App Server error" 'ade-error)
(define-error 'ade-app-server-disconnected-error
  "ADE App Server connection is disconnected"
  'ade-app-server-error)
(define-error 'ade-app-server-request-error
  "ADE App Server request failed"
  'ade-app-server-error)
(define-error 'ade-app-server-protocol-error
  "ADE App Server protocol error"
  'ade-app-server-error)
(define-error 'ade-app-server-request-already-answered
  "ADE App Server request was already answered"
  'ade-app-server-error)

;; A test or embedding can provide a function with the following signature:
;;
;;   (URL ON-OPEN ON-MESSAGE ON-ERROR ON-CLOSE) -> transport handle
;;
;; The callbacks may be called with any extra arguments.  The normal factory
;; is installed lazily so loading ADE does not require websocket.el in batch
;; tests.
(defvar ade-app-server-transport-factory nil
  "Optional websocket factory used instead of websocket.el.")

(cl-defstruct (ade-app-server
               (:constructor ade-app-server--make))
  "One persistent JSON-RPC connection to an App Server.

The `pending-requests' and `server-requests' tables are intentionally kept
per connection.  A request ID has no meaning across connections, and an
Agent never shares a reader with another Agent."
  url
  client-name
  client-title
  client-version
  capabilities
  transport-factory
  send-function
  close-function
  websocket
  transport-open-p
  handshake-p
  ever-connected-p
  intentional-close-p
  next-id
  pending-requests
  server-requests
  on-event
  on-request
  on-connected
  on-reconnected
  on-disconnected
  on-protocol-error
  reconnect-timer
  reconnect-attempt
  reconnecting-p)

(defun ade-app-server-create (&rest options)
  "Create an App Server connection from keyword OPTIONS.

Supported options include `:url', `:client-name', `:client-title',
`:client-version', `:capabilities', `:transport-factory', `:send-function',
`:close-function', and the callbacks `:on-event', `:on-request',
`:on-connected', `:on-reconnected', `:on-disconnected', and
`:on-protocol-error'.  No network connection is made until
`ade-app-server-connect' is called."
  (ade-app-server--make
   :url (or (plist-get options :url) ade-app-server-default-url)
   :client-name (or (plist-get options :client-name)
                    ade-app-server-client-name)
   :client-title (or (plist-get options :client-title) "Emacs ADE")
   :client-version (or (plist-get options :client-version)
                       ade-app-server-client-version)
   :capabilities (or (plist-get options :capabilities)
                     '((experimentalApi . t)))
   :transport-factory (or (plist-get options :transport-factory)
                          ade-app-server-transport-factory)
   :send-function (plist-get options :send-function)
   :close-function (plist-get options :close-function)
   :websocket nil
   :transport-open-p nil
   :handshake-p nil
   :ever-connected-p nil
   :intentional-close-p nil
   :next-id 1
   :pending-requests (make-hash-table :test #'equal)
   :server-requests (make-hash-table :test #'equal)
   :on-event (plist-get options :on-event)
   :on-request (plist-get options :on-request)
   :on-connected (plist-get options :on-connected)
   :on-reconnected (plist-get options :on-reconnected)
   :on-disconnected (plist-get options :on-disconnected)
   :on-protocol-error (plist-get options :on-protocol-error)
   :reconnect-timer nil
   :reconnect-attempt 0
   :reconnecting-p nil))

(defalias 'ade-app-server-new #'ade-app-server-create)

(defun ade-app-server--json-get (object key)
  "Return KEY from JSON OBJECT, accepting alist and plist objects."
  (let* ((name (cond
                ((keywordp key) (substring (symbol-name key) 1))
                ((symbolp key) (symbol-name key))
                (t key)))
         (symbol (and (stringp name) (intern name)))
         (keyword (and (stringp name) (intern (concat ":" name)))))
    (cond
     ((listp object)
      (or (alist-get symbol object nil nil #'equal)
          (alist-get name object nil nil #'equal)
          (plist-get object keyword)
          (plist-get object symbol)))
     (t nil))))

(defun ade-app-server--json-has-key-p (object key)
  "Return non-nil when JSON OBJECT contains KEY, even when its value is nil."
  (let* ((name (cond
                ((keywordp key) (substring (symbol-name key) 1))
                ((symbolp key) (symbol-name key))
                (t key)))
         (symbol (and (stringp name) (intern name)))
         (keyword (and (stringp name) (intern (concat ":" name)))))
    (and (listp object)
         (or (assoc symbol object)
             (assoc name object)
             (plist-member object keyword)
             (plist-member object symbol)))))

(defun ade-app-server--json-encode (object)
  "Encode JSON OBJECT without adding a JSON-RPC header envelope."
  (condition-case err
      (json-serialize object)
    (error
     (signal 'ade-app-server-protocol-error
             (list "Could not encode JSON-RPC message" object err)))))

(defun ade-app-server--json-decode (text)
  "Decode JSON TEXT into an alist with ordinary nil JSON nulls."
  (condition-case err
      (json-parse-string text :object-type 'alist :array-type 'list
                         :null-object nil :false-object :json-false)
    (error
     (signal 'ade-app-server-protocol-error
             (list "Could not decode App Server message" text err)))))

(defun ade-app-server--invoke (function &rest arguments)
  "Invoke FUNCTION with ARGUMENTS, accepting one-argument callbacks too."
  (when function
    (condition-case err
        (apply function arguments)
      (wrong-number-of-arguments
       (condition-case _
           (funcall function (car arguments))
         (error (signal (car err) (cdr err))))))))

(defun ade-app-server--frame-payload (frame)
  "Extract a text payload from websocket FRAME or return FRAME when text."
  (cond
   ((stringp frame) frame)
   ((and (fboundp 'websocket-frame-payload)
         (condition-case nil (websocket-frame-payload frame) (error nil))))
   ((and (listp frame)
         (or (alist-get 'payload frame) (alist-get "payload" frame))))
   ((and (listp frame) (plist-get frame :payload)))
   (t (format "%s" frame))))

(defun ade-app-server--default-transport-factory
    (url on-open on-message on-error on-close)
  "Open URL using websocket.el and wire its callbacks to ADE callbacks."
  (unless (require 'websocket nil t)
    (signal 'ade-app-server-error
            (list "websocket.el is not available" url)))
  (unless (fboundp 'websocket-open)
    (signal 'ade-app-server-error
            (list "websocket-open is not available" url)))
  (websocket-open
   url
   :on-open (lambda (websocket) (ade-app-server--invoke on-open websocket))
   :on-message (lambda (websocket frame)
                 (ade-app-server--invoke on-message websocket frame))
   :on-error (lambda (websocket type error)
               (ade-app-server--invoke on-error websocket type error))
   :on-close (lambda (websocket)
               (ade-app-server--invoke on-close websocket))))

(defun ade-app-server--default-close (websocket)
  "Close WEBSOCKET through websocket.el when possible."
  (when (and websocket (fboundp 'websocket-close))
    (websocket-close websocket)))

(defun ade-app-server-connected-p (connection)
  "Return non-nil when CONNECTION completed the initialize handshake."
  (and (ade-app-server-p connection)
       (ade-app-server-transport-open-p connection)
       (ade-app-server-handshake-p connection)))

(defun ade-app-server-handshake-complete-p (connection)
  "Return non-nil when CONNECTION completed initialize/initialized."
  (and (ade-app-server-p connection)
       (ade-app-server-handshake-p connection)))

(defun ade-app-server-pending-count (connection)
  "Return the number of outstanding client requests on CONNECTION."
  (hash-table-count (ade-app-server-pending-requests connection)))

(defun ade-app-server-server-request (connection request-id)
  "Return the server request record for REQUEST-ID on CONNECTION."
  (gethash request-id (ade-app-server-server-requests connection)))

(defun ade-app-server--send-wire (connection object &optional pre-handshake)
  "Send OBJECT as one unframed JSON text message on CONNECTION.

PRE-HANDSHAKE permits only the initialize/initialized exchange while the
underlying transport is open but the JSON-RPC handshake is not complete."
  (unless (and (ade-app-server-transport-open-p connection)
               (or pre-handshake
                   (ade-app-server-handshake-complete-p connection)))
    (signal 'ade-app-server-disconnected-error (list connection)))
  (let ((text (ade-app-server--json-encode object)))
    (condition-case err
        (if-let* ((sender (ade-app-server-send-function connection)))
            (funcall sender connection text)
          (unless (ade-app-server-websocket connection)
            (signal 'ade-app-server-disconnected-error (list connection)))
          (unless (fboundp 'websocket-send-text)
            (signal 'ade-app-server-error
                    (list "websocket-send-text is not available")))
          (websocket-send-text (ade-app-server-websocket connection) text))
      (error
       (signal 'ade-app-server-error
               (list "Failed to send App Server JSON-RPC message" err))))))

(defun ade-app-server-send-notification (connection method &optional params)
  "Send JSON-RPC notification METHOD with PARAMS on CONNECTION."
  (ade-app-server--send-wire
   connection (list (cons 'jsonrpc "2.0")
                    (cons 'method method)
                    (cons 'params (or params '())))
   (equal method "initialized"))
  t)

(defun ade-app-server-call
    (connection method &optional params callback errorback)
  "Call METHOD with PARAMS and return its JSON-RPC request ID.

CALLBACK receives RESULT, RESPONSE, and CONNECTION (or just RESULT when its
arity only accepts one argument).  ERRORBACK receives ERROR, RESPONSE, and
CONNECTION with the same arity fallback.  Requests are never re-sent by the
reconnect machinery; callers must reconcile and decide what to do next."
  (unless (or (and (equal method "initialize")
                  (ade-app-server-transport-open-p connection))
              (ade-app-server-connected-p connection))
    (signal 'ade-app-server-disconnected-error (list method)))
  (let* ((id (prog1 (ade-app-server-next-id connection)
               (setf (ade-app-server-next-id connection)
                     (1+ (ade-app-server-next-id connection)))))
         (message (list (cons 'jsonrpc "2.0")
                        (cons 'id id)
                        (cons 'method method)
                        (cons 'params (or params '()))))
         (record (list :id id :method method :params params
                       :callback callback :errorback errorback
                       :sent-at (float-time))))
    (puthash id record (ade-app-server-pending-requests connection))
    (condition-case err
        (progn
          (ade-app-server--send-wire connection message
                                      (equal method "initialize"))
          id)
      (error
       (remhash id (ade-app-server-pending-requests connection))
       (signal (car err) (cdr err))))))

(defalias 'ade-app-server-request #'ade-app-server-call)

(defun ade-app-server--initialize (connection)
  "Send the required App Server initialize handshake on CONNECTION."
  (ade-app-server-call
   connection "initialize"
   (list (cons 'clientInfo
               (list (cons 'name (ade-app-server-client-name connection))
                     (cons 'title (ade-app-server-client-title connection))
                     (cons 'version (ade-app-server-client-version connection))))
         (cons 'capabilities (ade-app-server-capabilities connection)))
   (lambda (_result)
     (condition-case err
         (progn
           (ade-app-server-send-notification connection "initialized" '())
           (setf (ade-app-server-handshake-p connection) t
                 (ade-app-server-transport-open-p connection) t
                 (ade-app-server-reconnecting-p connection) nil
                 (ade-app-server-reconnect-attempt connection) 0)
           (let ((reconnected (ade-app-server-ever-connected-p connection)))
             (setf (ade-app-server-ever-connected-p connection) t)
             (ade-app-server--invoke
              (if reconnected
                  (ade-app-server-on-reconnected connection)
                (ade-app-server-on-connected connection))
              connection)))
       (error
        (ade-app-server--protocol-failure connection err))))
   (lambda (error &rest _)
     (ade-app-server--protocol-failure connection error))))

(defun ade-app-server--on-open (connection websocket)
  "Handle a transport OPEN callback for CONNECTION."
  (setf (ade-app-server-websocket connection) websocket
        (ade-app-server-transport-open-p connection) t
        (ade-app-server-handshake-p connection) nil)
  (condition-case err
      (ade-app-server--initialize connection)
    (error (ade-app-server--protocol-failure connection err))))

(defun ade-app-server--transition-disconnected
    (connection reason &optional schedule)
  "Mark CONNECTION down once, fail its pending calls, and optionally retry.

The websocket library may report both an error and a close for one socket.
Clearing the transport handle before notifying callbacks makes this transition
idempotent and keeps a later close from duplicating Agent state changes."
  (let ((was-open (or (ade-app-server-transport-open-p connection)
                      (ade-app-server-handshake-p connection)
                      (ade-app-server-websocket connection))))
    (setf (ade-app-server-transport-open-p connection) nil
          (ade-app-server-handshake-p connection) nil
          (ade-app-server-websocket connection) nil)
    (ade-app-server--fail-pending connection reason)
    (when was-open
      (ade-app-server--invoke (ade-app-server-on-disconnected connection)
                              connection reason))
    (when (and schedule
               (not (ade-app-server-intentional-close-p connection)))
      (ade-app-server--schedule-reconnect connection))
    was-open))

(defun ade-app-server--protocol-failure (connection error)
  "Mark CONNECTION failed and schedule reconnect after ERROR."
  (ade-app-server--invoke (ade-app-server-on-protocol-error connection)
                          connection error)
  (ade-app-server--transition-disconnected connection error t))

(defun ade-app-server--fail-pending (connection error)
  "Fail and clear all client requests on CONNECTION after a disconnect."
  (let ((records nil))
    (maphash (lambda (_id record) (push record records))
             (ade-app-server-pending-requests connection))
    (clrhash (ade-app-server-pending-requests connection))
    (dolist (record records)
      (ade-app-server--invoke
       (plist-get record :errorback)
       error
       (list (cons 'id (plist-get record :id))
             (cons 'error error))
       connection))))

(defun ade-app-server--on-message (_connection frame)
  "Placeholder callback; the connection argument is supplied by closure."
  (ignore frame))

(defun ade-app-server--on-close (connection &rest _)
  "Handle a transport CLOSE callback for CONNECTION."
  (ade-app-server--transition-disconnected
   connection (list 'ade-app-server-disconnected "socket closed") t))

(defun ade-app-server--on-error (connection &rest details)
  "Handle a transport ERROR callback for CONNECTION."
  (ade-app-server--invoke (ade-app-server-on-protocol-error connection)
                          connection details)
  ;; websocket.el normally follows an error with on-close.  Transition here as
  ;; well for transports which report only on-error; the idempotent helper
  ;; prevents duplicate failure callbacks when on-close follows.
  (ade-app-server--transition-disconnected connection details t))

(defun ade-app-server-connect (connection)
  "Open CONNECTION and begin its initialize handshake."
  (unless (ade-app-server-p connection)
    (signal 'ade-app-server-error (list "Not an App Server connection")))
  (when-let* ((timer (ade-app-server-reconnect-timer connection)))
    (cancel-timer timer)
    (setf (ade-app-server-reconnect-timer connection) nil))
  (setf (ade-app-server-intentional-close-p connection) nil
        (ade-app-server-reconnecting-p connection) nil)
  (let ((factory (or (ade-app-server-transport-factory connection)
                     #'ade-app-server--default-transport-factory)))
    (condition-case err
        (setf (ade-app-server-websocket connection)
              (funcall factory
                       (ade-app-server-url connection)
                       (lambda (websocket)
                         (ade-app-server--on-open connection websocket))
                       (lambda (websocket frame)
                         (ignore websocket)
                         (condition-case decode-error
                             (ade-app-server--handle-message
                              connection (ade-app-server--frame-payload frame))
                           (error
                            (ade-app-server--protocol-failure
                             connection decode-error))))
                       (lambda (&rest details)
                         (apply #'ade-app-server--on-error connection details))
                       (lambda (&rest details)
                         (apply #'ade-app-server--on-close connection details))))
      (error
       (ade-app-server--protocol-failure connection err))))
  connection)

(defun ade-app-server--schedule-reconnect (connection)
  "Schedule one bounded exponential reconnect for CONNECTION."
  (when (and (not (ade-app-server-intentional-close-p connection))
             (null (ade-app-server-reconnect-timer connection))
             (or (null ade-app-server-reconnect-max-attempts)
                 (< (ade-app-server-reconnect-attempt connection)
                    ade-app-server-reconnect-max-attempts)))
    (let* ((attempt (ade-app-server-reconnect-attempt connection))
           (delay (min ade-app-server-reconnect-max-delay
                       (* ade-app-server-reconnect-base-delay
                          (expt 2 attempt)))))
      (setf (ade-app-server-reconnect-attempt connection)
            (1+ attempt)
            (ade-app-server-reconnecting-p connection) t
            (ade-app-server-reconnect-timer connection)
            (run-at-time delay nil #'ade-app-server--reconnect connection)))))

(defun ade-app-server--reconnect (connection)
  "Run one scheduled reconnect for CONNECTION."
  (setf (ade-app-server-reconnect-timer connection) nil)
  (unless (ade-app-server-intentional-close-p connection)
    (ade-app-server-connect connection)))

(defun ade-app-server-disconnect (connection &optional intentional)
  "Close CONNECTION.

When INTENTIONAL is non-nil, no reconnect is scheduled.  Unexpected
transport closure always uses the reconnect path."
  (when (ade-app-server-p connection)
    (let ((websocket (ade-app-server-websocket connection)))
      (setf (ade-app-server-intentional-close-p connection) intentional)
      (when-let* ((timer (ade-app-server-reconnect-timer connection)))
        (cancel-timer timer)
        (setf (ade-app-server-reconnect-timer connection) nil))
      (ade-app-server--transition-disconnected
       connection (list 'ade-app-server-disconnected "connection closed") nil)
      (when-let* ((closer (ade-app-server-close-function connection)))
        (ignore-errors (funcall closer websocket)))
      (unless (ade-app-server-close-function connection)
        (ignore-errors (ade-app-server--default-close websocket)))))
  t)

(defalias 'ade-app-server-close #'ade-app-server-disconnect)

(defun ade-app-server--handle-response (connection message)
  "Dispatch a JSON-RPC RESPONSE MESSAGE for CONNECTION."
  (let* ((id (ade-app-server--json-get message 'id))
         (record (gethash id (ade-app-server-pending-requests connection)))
         (error-object (ade-app-server--json-get message 'error)))
    (when record
      (remhash id (ade-app-server-pending-requests connection))
      (if error-object
          (ade-app-server--invoke (plist-get record :errorback)
                                  error-object message connection)
        (ade-app-server--invoke (plist-get record :callback)
                                (ade-app-server--json-get message 'result)
                                message connection)))))

(defun ade-app-server--handle-server-request (connection message)
  "Record and dispatch a server REQUEST MESSAGE for CONNECTION."
  (let* ((id (ade-app-server--json-get message 'id))
         (existing (gethash id (ade-app-server-server-requests connection))))
    (or existing
        (let ((record (list :id id
                            :method (ade-app-server--json-get message 'method)
                            :params (ade-app-server--json-get message 'params)
                            :state 'pending
                            :received-at (float-time))))
          (puthash id record (ade-app-server-server-requests connection))
          (ade-app-server--invoke (ade-app-server-on-request connection)
                                  connection record message)
          (ade-app-server--invoke (ade-app-server-on-event connection)
                                  connection message)
          record))))

(defun ade-app-server--handle-event (connection message)
  "Dispatch a JSON-RPC notification MESSAGE for CONNECTION."
  (let ((method (ade-app-server--json-get message 'method)))
    (when (equal method "serverRequest/resolved")
      (let* ((params (ade-app-server--json-get message 'params))
             (request-id (ade-app-server--json-get params 'requestId))
             (record (gethash request-id
                              (ade-app-server-server-requests connection))))
        (when record
          (setf (plist-get record :state) 'resolved
                (plist-get record :resolved-at) (float-time)))))
    (ade-app-server--invoke (ade-app-server-on-event connection)
                            connection message)))

(defun ade-app-server--handle-message (connection text)
  "Decode and dispatch one websocket TEXT message for CONNECTION."
  (let* ((message (if (stringp text)
                      (ade-app-server--json-decode text)
                    text))
         (has-method (ade-app-server--json-has-key-p message 'method))
         (has-id (ade-app-server--json-has-key-p message 'id)))
    (cond
     ((and has-method has-id)
      (ade-app-server--handle-server-request connection message))
     ((and has-id
           (or (ade-app-server--json-has-key-p message 'result)
               (ade-app-server--json-has-key-p message 'error)))
      (ade-app-server--handle-response connection message))
     (has-method
      (ade-app-server--handle-event connection message))
     (t
      (ade-app-server--invoke (ade-app-server-on-protocol-error connection)
                              connection
                              (list 'unrecognized-message message)))))
  t)

(defun ade-app-server-respond-server-request
    (connection request-id result &optional on-success on-failure)
  "Respond once to server REQUEST-ID with RESULT.

The request transitions pending -> responding before the wire send.  A
`serverRequest/resolved' notification transitions it to resolved.  A send
failure rolls it back to pending, allowing an explicit retry.  A second
response after responding or resolved signals
`ade-app-server-request-already-answered'."
  (let ((record (gethash request-id
                        (ade-app-server-server-requests connection))))
    (unless record
      (signal 'ade-app-server-request-error
              (list "Unknown server request" request-id)))
    (unless (eq (plist-get record :state) 'pending)
      (signal 'ade-app-server-request-already-answered
              (list request-id (plist-get record :state))))
    (setf (plist-get record :state) 'responding
          (plist-get record :response) result)
    (condition-case err
        (progn
          (ade-app-server--send-wire
           connection (list (cons 'jsonrpc "2.0")
                            (cons 'id request-id)
                            (cons 'result result)))
          (ade-app-server--invoke on-success record)
          t)
      (error
       (setf (plist-get record :state) 'pending
             (plist-get record :failure) err)
       (ade-app-server--invoke on-failure record err)
       nil))))

(defalias 'ade-app-server-respond #'ade-app-server-respond-server-request)

(provide 'ade-app-server)

;;; ade-app-server.el ends here
