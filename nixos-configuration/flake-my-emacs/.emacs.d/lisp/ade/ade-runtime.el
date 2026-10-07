;;; ade-runtime.el --- Owned local Codex App Server runtime -*- lexical-binding: t; -*-

;;; Commentary:

;; This is the one-session owner for the local App Server process.  It is
;; deliberately separate from `ade-app-server.el': the latter consumes a
;; websocket endpoint, while this file owns starting and stopping exactly one
;; `codex app-server' process and discovering its ephemeral localhost port.
;; Loading the library has no process, buffer, or UI side effect.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-parse)
(require 'ade-core)
(require 'ade-agent)
(require 'ade-ghostel)

(defgroup ade-runtime nil
  "Owned local Codex App Server runtime for ADE."
  :group 'ade)

(defcustom ade-runtime-program "codex"
  "Codex executable used for the owned local App Server."
  :type 'string
  :group 'ade-runtime)

(defcustom ade-runtime-start-timeout 5.0
  "Maximum seconds to wait for the App Server listening URL."
  :type 'number
  :group 'ade-runtime)

(defconst ade-runtime-listen-url "ws://127.0.0.1:0"
  "Ephemeral loopback URL requested from the owned App Server process.

This is intentionally not customizable to prevent an ADE runtime from
silently becoming a non-local server.  The final port is learned from the
process output and is validated again before use.")

(define-error 'ade-runtime-error "ADE runtime error" 'ade-error)
(define-error 'ade-runtime-timeout-error
  "ADE App Server did not report a listening URL in time"
  'ade-runtime-error)
(define-error 'ade-runtime-nonlocal-error
  "ADE App Server reported a non-local websocket URL"
  'ade-runtime-error)

;; The factory contract is intentionally process-like but does not require a
;; real Emacs process, which keeps ERT isolated:
;;
;;   (PROGRAM ARGS ON-OUTPUT ON-EXIT) -> PROCESS
;;
;; ON-OUTPUT receives combined stdout/stderr chunks.  ON-EXIT receives one
;; sentinel event.  The returned PROCESS may be an Emacs process or a fake
;; plist understood by the private live/stop helpers below.
(defvar ade-runtime-process-function nil
  "Optional `(PROGRAM ARGS ON-OUTPUT ON-EXIT) -> PROCESS' factory.

The normal factory uses `make-process' with `:noquery t'.")

(cl-defstruct (ade-runtime
               (:constructor ade-runtime--make))
  "One ADE-owned local App Server process and its discovered endpoint."
  process url state output reason started-at stopping-p owner-p)

(defvar ade-runtime--current nil
  "The one process-local ADE runtime record, or nil before first start.")

(defun ade-runtime-current ()
  "Return the current session-local runtime record, if any."
  ade-runtime--current)

(defun ade-runtime-running-p (&optional runtime)
  "Return non-nil when RUNTIME owns a live process and a validated URL."
  (let ((runtime (or runtime ade-runtime--current)))
    (and (ade-runtime-p runtime)
         (eq (ade-runtime-state runtime) 'running)
         (ade-runtime-url runtime)
         (ade-runtime--process-live-p (ade-runtime-process runtime)))))

(defun ade-runtime--invoke (function &rest arguments)
  "Invoke FUNCTION with ARGUMENTS, accepting one-argument callbacks too."
  (when function
    (condition-case err
        (apply function arguments)
      (wrong-number-of-arguments
       (condition-case _
           (funcall function (car arguments))
         (error (signal (car err) (cdr err))))))))

(defun ade-runtime--process-live-p (process)
  "Return non-nil when PROCESS is live, including supported fake handles."
  (cond
   ((processp process) (process-live-p process))
   ((and (listp process) (functionp (plist-get process :live-p)))
    (funcall (plist-get process :live-p) process))
   ((listp process) (plist-get process :live))
   (t nil)))

(defun ade-runtime--stop-process (process)
  "Stop PROCESS through its owned handle, if it is live."
  (when (and process (ade-runtime--process-live-p process))
    (cond
     ((processp process)
      (set-process-query-on-exit-flag process nil)
      (delete-process process))
     ((functionp (plist-get process :stop))
      (funcall (plist-get process :stop) process))
     (t nil))))

(defun ade-runtime--default-process (program args on-output on-exit)
  "Start PROGRAM ARGS with combined output and no query on exit."
  (let ((buffer (generate-new-buffer "*ade-app-server*")))
    (condition-case err
        (let ((process
               (make-process
                :name "ade-app-server"
                :buffer buffer
                :command (cons program args)
                :connection-type 'pipe
                :noquery t
                :filter (lambda (_process chunk)
                          (funcall on-output chunk))
                :sentinel (lambda (process event)
                            (when (memq (process-status process)
                                        '(exit signal closed failed))
                              (funcall on-exit event))))))
          ;; Be explicit even though `:noquery' is supplied above: the owned
          ;; runtime must never create an exit prompt in an Emacs session.
          (set-process-query-on-exit-flag process nil)
          process)
      (error
       (when (buffer-live-p buffer) (kill-buffer buffer))
       (signal (car err) (cdr err))))))

(defun ade-runtime--url-local-p (url)
  "Return non-nil when URL is a websocket endpoint on loopback only."
  (condition-case nil
      (let* ((parsed (url-generic-parse-url url))
             (type (url-type parsed))
             (host (downcase (or (url-host parsed) "")))
             (port (url-port parsed)))
        (and (equal type "ws")
             (member host '("127.0.0.1" "localhost" "::1" "[::1]"))
             (integerp port)
             (> port 0)
             (<= port 65535)))
    (error nil)))

(defun ade-runtime--extract-url (output)
  "Extract and validate a `listening on:' websocket URL from OUTPUT."
  (when (string-match
         "listening on:[[:space:]]+\\(ws://[^ \t\r\n]+\\)"
         output)
    (let ((url (string-trim (match-string 1 output))))
      (unless (ade-runtime--url-local-p url)
        (signal 'ade-runtime-nonlocal-error (list url)))
      url)))

(defun ade-runtime--clear-endpoint (runtime state reason)
  "Clear RUNTIME endpoint and set STATE/REASON."
  (setf (ade-runtime-url runtime) nil
        (ade-runtime-state runtime) state
        (ade-runtime-reason runtime) reason)
  runtime)

(defun ade-runtime--process-output (runtime chunk)
  "Consume combined process CHUNK for RUNTIME."
  (setf (ade-runtime-output runtime)
        (concat (or (ade-runtime-output runtime) "") chunk))
  (when (eq (ade-runtime-state runtime) 'starting)
    (condition-case err
        (when-let* ((url (ade-runtime--extract-url
                          (ade-runtime-output runtime))))
          (setf (ade-runtime-url runtime) url))
      (ade-runtime-nonlocal-error
       (ade-runtime--clear-endpoint runtime 'unknown err)
       ;; The process is ours, so rejecting an untrusted endpoint also stops
       ;; it.  The start caller reports the error and never connects to it.
       (ade-runtime--stop-process (ade-runtime-process runtime)))
      (error
       (ade-runtime--clear-endpoint runtime 'unknown err)
       (ade-runtime--stop-process (ade-runtime-process runtime))))))

(defun ade-runtime--process-exited (runtime event)
  "Handle the owned process EVENT and forget its endpoint."
  (ade-runtime--disconnect-agents runtime event)
  (setf (ade-runtime-process runtime) nil)
  (unless (eq (ade-runtime-state runtime) 'stopped)
    (ade-runtime--clear-endpoint runtime 'unknown event)))

(defun ade-runtime--disconnect-agents (runtime reason)
  "Disconnect Agents using RUNTIME's owned endpoint and retain their records."
  (let ((url (ade-runtime-url runtime)))
    (when url
      (dolist (workspace (ade-core-workspaces))
        (dolist (agent-id (ade-workspace-agent-ids workspace))
          (when-let* ((agent (ade-core-agent-by-id agent-id)))
            (when (equal (ade-agent--metadata-get agent :endpoint) url)
              ;; Intentional disconnect cancels transport reconnect timers.
              ;; The retained Agent is then marked unknown from an explicit
              ;; runtime lifecycle fact, never from terminal output.
              (ade-agent-disconnect agent t)
              (ade-agent--apply-state-event
               agent (list :type 'connection-lost
                           :reason reason
                           :source 'app-server)))))))))

(defun ade-runtime--failure (runtime errorback error)
  "Stop failed RUNTIME, invoke ERRORBACK, and signal ERROR."
  (ade-runtime--stop-process (ade-runtime-process runtime))
  (setf (ade-runtime-process runtime) nil)
  (ade-runtime--clear-endpoint runtime 'unknown error)
  (ade-runtime--invoke errorback runtime error)
  (signal (if (symbolp (car-safe error)) (car error)
            'ade-runtime-error)
          (if (and (consp error) (symbolp (car error)))
              (cdr error)
            (list error))))

(defun ade-runtime--wait-for-url (runtime)
  "Wait a finite amount of time for RUNTIME's endpoint."
  (let ((deadline (+ (float-time) (max 0 ade-runtime-start-timeout))))
    (while (and (eq (ade-runtime-state runtime) 'starting)
                (null (ade-runtime-url runtime))
                (< (float-time) deadline))
      ;; `accept-process-output' also services websocket/process callbacks.
      ;; A nil process is valid for a fake factory and still gives the event
      ;; loop a bounded chance to run.
      (accept-process-output nil 0.05)))
  (and (eq (ade-runtime-state runtime) 'starting)
       (ade-runtime-url runtime)))

(defun ade-runtime-start (&optional callback errorback)
  "Explicitly start the one owned local App Server and return its record.

The process command is fixed to `codex app-server --listen ws://127.0.0.1:0'.
Repeated calls while the owned process is starting/running do not launch a
second process.  CALLBACK receives the runtime after a validated URL appears;
ERRORBACK receives RUNTIME and ERROR before a start failure is signaled."
  (interactive)
  (let ((existing ade-runtime--current))
    (cond
     ((and existing
           (memq (ade-runtime-state existing) '(starting running))
           (ade-runtime--process-live-p (ade-runtime-process existing)))
      (when (and callback (eq (ade-runtime-state existing) 'running))
        (ade-runtime--invoke callback existing))
      existing)
     (t
      (let* ((runtime (ade-runtime--make
                       :process nil :url nil :state 'starting :output ""
                       :reason nil :started-at (float-time)
                       :stopping-p nil :owner-p t))
             (factory (or ade-runtime-process-function
                          #'ade-runtime--default-process))
             (on-output (lambda (chunk)
                          (ade-runtime--process-output runtime chunk)))
             (on-exit (lambda (event)
                        (ade-runtime--process-exited runtime event))))
        (setq ade-runtime--current runtime)
        (condition-case err
            (setf (ade-runtime-process runtime)
                  (funcall factory ade-runtime-program
                           (list "app-server" "--listen"
                                 ade-runtime-listen-url)
                           on-output on-exit))
          (error
           (ade-runtime--failure runtime errorback err)))
        (unless (ade-runtime-process runtime)
          (ade-runtime--failure
           runtime errorback
           (list 'ade-runtime-error "Process factory returned nil")))
        (unless (ade-runtime--wait-for-url runtime)
          (ade-runtime--failure
           runtime errorback
           (if (eq (ade-runtime-state runtime) 'unknown)
               (or (ade-runtime-reason runtime)
                   (list 'ade-runtime-error "App Server exited"))
             (list 'ade-runtime-timeout-error
                   ade-runtime-start-timeout))))
        (setf (ade-runtime-state runtime) 'running)
        (ade-runtime--invoke callback runtime)
        runtime)))))

(defun ade-runtime-stop ()
  "Stop only the App Server process owned by the current runtime.

No arbitrary PID, external App Server, websocket, or Agent process is
stopped.  The runtime record remains available with a cleared URL so callers
can inspect the stopped state and explicitly start a fresh owner later."
  (interactive)
  (when-let* ((runtime ade-runtime--current))
    (setf (ade-runtime-stopping-p runtime) t)
    (ade-runtime--disconnect-agents runtime 'explicit-runtime-stop)
    (ade-runtime--stop-process (ade-runtime-process runtime))
    (setf (ade-runtime-process runtime) nil
          (ade-runtime-url runtime) nil
          (ade-runtime-state runtime) 'stopped
          (ade-runtime-reason runtime) 'explicit-stop
          (ade-runtime-stopping-p runtime) nil))
  t)

(defun ade-runtime--agent-failure (agent errorback error)
  "Mark AGENT unknown and call ERRORBACK without retrying a mutation."
  (setf (ade-agent-state agent) 'unknown
        (ade-agent-reason agent) error
        (ade-agent-lifecycle agent) 'failed)
  (ade-runtime--invoke errorback agent error)
  nil)

(defun ade-runtime--launch-agent-tui
    (agent callback errorback)
  "Register AGENT explicitly, then launch its remote TUI."
  (condition-case err
      (progn
        ;; This is the first core registration and is deliberately after the
        ;; initialize handshake and thread/start response.
        (ade-agent-register-after-handshake agent t)
        ;; A TUI launch failure must not remove the already registered record.
        (ade-ghostel-start
         agent nil nil
         (lambda (ready-agent)
           (ade-runtime--invoke callback ready-agent)))
        agent)
    (error
     (ade-runtime--agent-failure agent errorback err))))

(defun ade-runtime--start-agent-thread
    (agent model effort callback errorback)
  "Start AGENT's initial thread and then launch its remote TUI."
  (condition-case err
      (ade-agent-thread-start
       agent
       (let ((params (list (cons 'cwd
                                (ade-agent--metadata-get agent :root)))))
         (when model (push (cons 'model model) params))
         (when effort (push (cons 'effort effort) params))
         (when params (nreverse params)))
       (lambda (started-agent _result)
         (ade-runtime--launch-agent-tui
          started-agent callback errorback))
       (lambda (_failed-agent thread-error)
         (ade-runtime--agent-failure agent errorback thread-error)))
    (error
     (ade-runtime--agent-failure agent errorback err))))

(defun ade-runtime-start-agent (&rest options)
  "Create and explicitly start one Agent in the current Workspace.

OPTIONS accepts `:model', `:effort', `:callback', and `:errorback'.  The
sequence is: create an unregistered Agent with the current Workspace root,
connect it to the owned runtime, issue `thread/start', register/select it only
after handshake success, and launch `codex --remote URL resume THREAD_ID'
through Ghostel.  No prompt or automatic retry is sent.  A post-registration
Ghostel failure reports through ERRORBACK while retaining the Agent record."
  (let* ((workspace (ade-core-current-workspace))
         (model (plist-get options :model))
         (effort (plist-get options :effort))
         (callback (plist-get options :callback))
         (errorback (plist-get options :errorback)))
    (unless workspace
      (signal 'ade-no-current-workspace-error nil))
    (let* ((root (ade-workspace-root workspace))
           (agent (ade-agent-new
                   :workspace-uuid (ade-workspace-uuid workspace)
                   :root root
                   :endpoint nil
                   :model model
                   :effort effort
                   :source 'app-server)))
      (condition-case err
          (ade-runtime-start
           (lambda (runtime)
             (ade-agent--metadata-put agent :endpoint
                                      (ade-runtime-url runtime))
             (condition-case connect-error
                 (ade-agent-connect
                  agent
                  (lambda (connected-agent)
                    (ade-runtime--start-agent-thread
                     connected-agent model effort callback errorback)))
               (error
                (ade-runtime--agent-failure
                 agent errorback connect-error))))
           (lambda (_runtime runtime-error)
             (ade-runtime--agent-failure agent errorback runtime-error)))
        (error
         ;; `ade-runtime-start' already called its errorback.  Preserve the
         ;; original signal for callers that use the synchronous API.
         (unless (eq (ade-agent-lifecycle agent) 'failed)
           (ade-runtime--agent-failure agent errorback err))
         (signal (car err) (cdr err))))
      agent)))

(provide 'ade-runtime)

;;; ade-runtime.el ends here
