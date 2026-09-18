;;; ade-protocol-test.el --- Pure fake-transport ADE protocol tests -*- lexical-binding: t; -*-

;;; Commentary:

;; These tests use no socket, Ghostel process, Perspective, or window.  The
;; fake transport records plain JSON-RPC text and drives callbacks directly.

;;; Code:

(require 'ert)
(require 'json)
(add-to-list 'load-path
             (expand-file-name "../.emacs.d/lisp/ade"
                               (file-name-directory (or load-file-name
                                                        buffer-file-name))))
(require 'ade-core)
(require 'ade-state)
(require 'ade-app-server)
(require 'ade-agent)
(require 'ade-request)
(require 'ade-model)
(require 'ade-ghostel)
(require 'ade-send)
(require 'ade-side)

(defvar ade-test--transport nil)

(defun ade-test--factory (url on-open on-message on-error on-close)
  "Return a fake transport and retain URL/callbacks for a test."
  (setq ade-test--transport
        (list :url url :on-open on-open :on-message on-message
              :on-error on-error :on-close on-close :sent nil :closed nil))
  ade-test--transport)

(defun ade-test--send (_connection text)
  "Record TEXT on the fake transport."
  (setf (plist-get ade-test--transport :sent)
        (append (plist-get ade-test--transport :sent) (list text)))
  t)

(defun ade-test--sent-json (&optional index)
  "Decode sent JSON at INDEX, defaulting to the last message."
  (let* ((sent (plist-get ade-test--transport :sent))
         (text (if index (nth index sent) (car (last sent)))))
    (json-parse-string text :object-type 'alist :array-type 'list
                       :null-object nil :false-object :json-false)))

(defun ade-test--receive (text)
  "Drive the fake transport's message callback with TEXT."
  (funcall (plist-get ade-test--transport :on-message)
           ade-test--transport text))

(defun ade-test--workspace ()
  "Create and register one test Workspace."
  (let ((workspace
         (ade-workspace-create
          :uuid "ws-test-0001" :name "protocol-test" :root "/tmp"
          :worktree nil :perspective-name "ws-test-0001"
          :prompt-buffer nil :agent-ids nil :selected-agent-id nil
          :metadata nil)))
    (ade-core-register-workspace workspace)
    workspace))

(defun ade-test--agent ()
  "Create and register one idle test Agent with a fake connection."
  (let* ((workspace (ade-test--workspace))
         (agent (ade-agent-new
                 :id "agent-test-0001"
                 :workspace-uuid (ade-workspace-uuid workspace)
                 :thread-id "thread-test-0001"
                 :root "/tmp"
                 :model "gpt-test"))
         (connection
          (ade-app-server-create
           :url "ws://127.0.0.1:47321"
           :transport-factory #'ade-test--factory
           :send-function #'ade-test--send
           :on-request (lambda (conn _record message)
                         (ade-request-ingest agent conn message))
           :on-event (lambda (_conn message)
                       (when (equal (alist-get 'method message)
                                    "serverRequest/resolved")
                         (ade-request-resolved
                          agent
                          (alist-get 'requestId
                                     (alist-get 'params message))))))))
    (setf (ade-agent-connection agent) connection
          (ade-agent-state agent) 'idle)
    (ade-core-register-agent agent t)
    (ade-app-server-connect connection)
    (funcall (plist-get ade-test--transport :on-open) ade-test--transport)
    ;; initialize is always request id 1 for a fresh connection.
    (ade-test--receive
     "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"userAgent\":\"fake\"}}")
    (list agent connection)))

(defmacro ade-test--with-clean-state (&rest body)
  "Run BODY with all in-memory ADE protocol registries reset."
  `(progn
     (ade-core-reset)
     (ade-request-reset)
     (ade-side-reset)
     (ade-model-reset-cache)
     (setq ade-test--transport nil)
     (unwind-protect
         (progn ,@body)
       (ade-core-reset)
       (ade-request-reset)
       (ade-side-reset)
       (ade-model-reset-cache))))

(ert-deftest ade-protocol-initialize-uses-plain-jsonrpc-and-experimental-api ()
  (ade-test--with-clean-state
   (let* ((connection
           (ade-app-server-create
            :url "ws://127.0.0.1:47321"
            :transport-factory #'ade-test--factory
            :send-function #'ade-test--send))
          (opened nil))
     (setf (ade-app-server-on-connected connection)
           (lambda (_connection) (setq opened t)))
     (ade-app-server-connect connection)
     (funcall (plist-get ade-test--transport :on-open) ade-test--transport)
     (let ((initialize (ade-test--sent-json 0)))
       (should (equal (alist-get 'jsonrpc initialize) "2.0"))
       (should (equal (alist-get 'method initialize) "initialize"))
       (should-not (alist-get 'Content-Length initialize))
       (should (equal (alist-get 'experimentalApi
                                  (alist-get 'capabilities
                                             (alist-get 'params initialize)))
                      t)))
     (ade-test--receive
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"userAgent\":\"fake\"}}")
     (should (ade-app-server-connected-p connection))
     (should (ade-app-server-handshake-complete-p connection))
     (should opened)
     (should (equal (alist-get 'method (ade-test--sent-json 1))
                    "initialized")))))

(ert-deftest ade-protocol-server-request-is-exclusive-and-resolved ()
  (ade-test--with-clean-state
   (pcase-let ((`(,agent ,connection) (ade-test--agent)))
     (ade-test--receive
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"item/commandExecution/requestApproval\",\"params\":{\"threadId\":\"thread-test-0001\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\",\"availableDecisions\":[\"accept\",\"cancel\"]}}")
     (let ((request (ade-request-by-id 7 connection)))
       (should (ade-request-p request))
       (should (eq (ade-request-status request) 'pending))
       (should (= 1 (length (ade-request-pending-for-agent agent))))
       (should (= 2 (length (ade-request-choices request))))
       (should (ade-request-respond request "cancel"))
       (should (eq (ade-request-status request) 'responding))
       (should-not (ade-request-pending-p request))
       (should (ade-request-outstanding-p request))
       (should-error (ade-request-respond request "cancel")
                     :type 'ade-request-already-resolved-error)
       (ade-test--receive
        "{\"jsonrpc\":\"2.0\",\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-test-0001\",\"requestId\":7}}")
       (should (eq (ade-request-status request) 'resolved))
       (should-not (ade-request-pending-for-agent agent))))))

(ert-deftest ade-protocol-origin-is-ade-only-for-known-client-id ()
  (ade-test--with-clean-state
   (pcase-let ((`(,agent ,_connection) (ade-test--agent)))
     (ade-agent-remember-client-message agent "ade-client-1" 'ade)
     (ade-agent--on-event
      agent nil
      '((method . "turn/started")
        (params (threadId . "thread-test-0001")
                (turn (id . "turn-1")))))
     (ade-agent--on-event
      agent nil
      '((method . "item/completed")
        (params (threadId . "thread-test-0001")
                (item (type . "userMessage")
                      (clientId . "ade-client-1")))))
     (should (eq (ade-agent-turn-origin agent) 'ade))
     (ade-agent--on-event
      agent nil
        '((method . "item/completed")
        (params (threadId . "thread-test-0001")
                (item (type . "userMessage") (clientId . nil)))))
     (should (eq (ade-agent-turn-origin agent) 'unknown))
     ;; A completed ADE turn keeps ownership through the authoritative idle
     ;; status.  A newly started turn without an ADE client id becomes unknown.
     (ade-agent-remember-client-message agent "ade-client-2" 'ade)
     (ade-agent--on-event
      agent nil
      '((method . "turn/started")
        (params (threadId . "thread-test-0001")
                (turn (id . "turn-2")))))
     (ade-agent--on-event
      agent nil
      '((method . "item/completed")
        (params (threadId . "thread-test-0001")
                (item (type . "userMessage")
                      (clientId . "ade-client-2")))))
     (ade-agent--on-event
      agent nil
      '((method . "turn/completed")
        (params (threadId . "thread-test-0001")
                (turn (id . "turn-2") (status . "completed")))))
     (should (eq (ade-agent-turn-origin agent) 'ade))
     (ade-agent--on-event
      agent nil
      '((method . "thread/status/changed")
        (params (threadId . "thread-test-0001")
                (status (type . "idle")))))
     (should (eq (ade-agent-state agent) 'idle))
     (should (eq (ade-agent-turn-origin agent) 'ade))
     (ade-agent--on-event
      agent nil
      '((method . "turn/started")
        (params (threadId . "thread-test-0001")
                (turn (id . "tui-turn-3")))))
     (should (eq (ade-agent-turn-origin agent) 'unknown)))))

(ert-deftest ade-protocol-explicit-takeover-allows-next-ade-turn ()
  (ade-test--with-clean-state
   (pcase-let ((`(,agent ,connection) (ade-test--agent)))
     (should-error (ade-send-turn agent "blocked until takeover")
                   :type 'ade-send-not-allowed-error)
     (should (ade-send-takeover agent (lambda (_agent) t)))
     (should (eq (ade-agent-turn-origin agent) 'ade))
     (should (= 2 (ade-send-turn agent "first ADE turn")))
     (ade-test--receive
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"turn\":{\"id\":\"ade-turn-1\"}}}")
     (let ((client-id
            (ade-send-snapshot-client-user-message-id
             (ade-agent-pending-send agent))))
       (ade-agent--on-event
        agent connection
        `((method . "item/completed")
          (params (threadId . "thread-test-0001")
                  (item (type . "userMessage")
                        (clientId . ,client-id)))))
       (ade-agent--on-event
        agent connection
        '((method . "turn/completed")
          (params (threadId . "thread-test-0001")
                  (turn (id . "ade-turn-1") (status . "completed")))))
       (ade-agent--on-event
        agent connection
        '((method . "thread/status/changed")
          (params (threadId . "thread-test-0001")
                  (status (type . "idle")))))
       ;; The completed ADE ownership carries into the next idle turn, so the
       ;; next explicit ADE send needs no hidden per-send takeover.
       (should (eq (ade-agent-turn-origin agent) 'ade))
       (should (= 3 (ade-send-turn agent "second ADE turn")))
       (should
               (equal (alist-get 'turnTrigger
                          (alist-get 'params (ade-test--sent-json 3)))
               "ade"))))))

(ert-deftest ade-protocol-steer-separates-success-and-failure-callbacks ()
  (ade-test--with-clean-state
   (pcase-let ((`(,agent ,connection) (ade-test--agent)))
     (ade-agent-set-current-turn-id agent "turn-steer")
     (ade-agent-set-turn-origin agent 'ade)
     (setf (ade-agent-state agent) 'working)
     (let ((success nil)
           (failure nil))
       (should (= 2
                  (ade-send-steer
                   agent "steer this"
                   "turn-steer"
                   (lambda (_agent _result) (setq success t))
                   (lambda (_agent _error) (setq failure t)))))
       (ade-test--receive
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32000,\"message\":\"stale turn\"}}")
       (should-not success)
       (should failure)))))

(ert-deftest ade-protocol-model-settings-broadcast-cache-and-tui-unknown-side ()
  (ade-test--with-clean-state
   (pcase-let ((`(,agent ,connection) (ade-test--agent)))
     (let ((result nil))
       (ade-model-list
        connection
        (lambda (models _connection) (setq result models)))
       ;; request id 2 follows initialize.
       (ade-test--receive
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"data\":[{\"id\":\"gpt-test\",\"model\":\"gpt-test\",\"hidden\":false}],\"nextCursor\":null}}")
       (should (equal (ade-model-find "gpt-test")
                      (car result))))
     (ade-agent--on-event
      agent connection
      '((method . "thread/settings/updated")
        (params (threadId . "thread-test-0001")
                (threadSettings (model . "gpt-test-2")))))
     (should (equal (ade-agent-model agent) "gpt-test-2"))
     (should-not (ade-side-known-p agent))
     (should-error (ade-side-close agent)
                   :type 'ade-side-unknown-error))))

(ert-deftest ade-protocol-send-accepted-clears-only-matching-snapshot ()
  (ade-test--with-clean-state
   (let ((agent (ade-agent-new :id "agent-test" :thread-id "thread-test")))
     (let ((snapshot
            (ade-send-snapshot--make
             :agent-id "agent-test" :thread-id "thread-test"
             :turn-id "turn-1" :client-user-message-id "client-1"
             :generation 1)))
       (ade-agent-set-pending-send agent snapshot)
       (should-not
        (ade-send-accepted-callback
         agent
         (ade-send-snapshot--make
          :agent-id "agent-test" :thread-id "thread-test"
          :turn-id "turn-old" :client-user-message-id "client-1"
          :generation 0)))
       (should (ade-agent-pending-send agent))
       (should
        (ade-send-accepted-callback agent snapshot))
       (should-not (ade-agent-pending-send agent))))))

(provide 'ade-protocol-test)

;;; ade-protocol-test.el ends here
