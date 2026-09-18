;;; ade-runtime-test.el --- Isolated owned App Server runtime tests -*- lexical-binding: t; -*-

;;; Commentary:

;; These tests use a fake runtime process, fake websocket transport, and an
;; in-memory pipe process for Ghostel.  They never start Codex, open a window,
;; or mutate the repository.

;;; Code:

(require 'ert)
(require 'json)
(add-to-list 'load-path
             (expand-file-name "../.emacs.d/lisp/ade"
                               (file-name-directory (or load-file-name
                                                        buffer-file-name))))
(require 'ade-core)
(require 'ade-app-server)
(require 'ade-agent)
(require 'ade-ghostel)
(require 'ade-runtime)

(defvar ade-runtime-test--processes nil)
(defvar ade-runtime-test--factory-count 0)
(defvar ade-runtime-test--transport nil)
(defvar ade-runtime-test--sent nil)
(defvar ade-runtime-test--ghostel-processes nil)
(defvar ade-runtime-test--ghostel-fails nil)

(defun ade-runtime-test--process-factory
    (program args on-output on-exit)
  "Create a fake PROCESS and immediately report a loopback endpoint."
  (setq ade-runtime-test--factory-count
        (1+ ade-runtime-test--factory-count))
  (let ((process (list :program program :args args :live t :noquery t)))
    (setf (plist-get process :on-output) on-output
          (plist-get process :on-exit) on-exit
          (plist-get process :stop)
          (lambda (handle)
            (setf (plist-get handle :live) nil)))
    (push process ade-runtime-test--processes)
    (funcall on-output "codex app-server\n")
    (funcall on-output "listening on: ws://127.0.0.1:43123\n")
    process))

(defun ade-runtime-test--silent-process-factory
    (program args on-output on-exit)
  "Create a fake process that never emits a listening URL."
  (ignore program args on-output on-exit)
  (let ((process (list :program program :args args :live t :noquery t)))
    (setf (plist-get process :stop)
          (lambda (handle)
            (setf (plist-get handle :live) nil)))
    (push process ade-runtime-test--processes)
    process))

(defun ade-runtime-test--nonlocal-process-factory
    (program args on-output on-exit)
  "Create a fake process that emits a rejected non-local endpoint."
  (ignore program args on-exit)
  (let ((process (list :program program :args args :live t :noquery t)))
    (setf (plist-get process :stop)
          (lambda (handle)
            (setf (plist-get handle :live) nil)))
    (push process ade-runtime-test--processes)
    (funcall on-output "listening on: ws://192.0.2.1:43123\n")
    process))

(defun ade-runtime-test--transport
    (url on-open on-message on-error on-close)
  "Create a fake websocket transport and retain its callbacks."
  (setq ade-runtime-test--transport
        (list :url url :on-open on-open :on-message on-message
              :on-error on-error :on-close on-close))
  ade-runtime-test--transport)

(defun ade-runtime-test--send (_connection text)
  "Record one fake websocket TEXT frame."
  (setq ade-runtime-test--sent
        (append ade-runtime-test--sent (list text)))
  t)

(defmacro ade-runtime-test--with-wire (&rest body)
  "Run BODY with the websocket sender replaced by the fake recorder."
  `(cl-letf (((symbol-function 'websocket-send-text)
              (lambda (_websocket text)
                (ade-runtime-test--send nil text))))
     ,@body))

(defun ade-runtime-test--receive (text)
  "Deliver TEXT to the retained fake websocket reader."
  (funcall (plist-get ade-runtime-test--transport :on-message)
           ade-runtime-test--transport text))

(defun ade-runtime-test--ghostel-exec
    (buffer program args identity)
  "Return an in-memory process for the Ghostel executor contract."
  (when ade-runtime-test--ghostel-fails
    (signal 'ade-runtime-error (list "fake Ghostel failure" identity)))
  (let ((process
         (make-pipe-process
          :name (format "ade-runtime-ghostel-%d"
                        (length ade-runtime-test--ghostel-processes))
          :buffer buffer
          :noquery t)))
    (push process ade-runtime-test--ghostel-processes)
    (list program args identity process)
    process))

(defun ade-runtime-test--workspace ()
  "Register one current Workspace rooted at the repository directory."
  (let ((workspace
         (ade-workspace-create
          :uuid "runtime-workspace"
          :name "runtime-workspace"
          :root (file-name-as-directory (expand-file-name default-directory))
          :worktree nil
          :perspective-name "runtime-workspace"
          :prompt-buffer nil
          :agent-ids nil
          :selected-agent-id nil
          :metadata nil)))
    (ade-core-register-workspace workspace)
    workspace))

(defmacro ade-runtime-test--clean (&rest body)
  "Run BODY with owned runtime and fake registries reset afterward."
  `(progn
     (ade-runtime-stop)
     (setq ade-runtime--current nil
           ade-runtime-test--processes nil
           ade-runtime-test--factory-count 0
           ade-runtime-test--transport nil
           ade-runtime-test--sent nil
           ade-runtime-test--ghostel-processes nil
           ade-runtime-test--ghostel-fails nil
           ade-runtime-process-function nil
           ade-app-server-transport-factory nil
           ade-ghostel-exec-function nil)
     (ade-core-reset)
     (unwind-protect
         (progn ,@body)
       (ade-runtime-stop)
       (dolist (process ade-runtime-test--ghostel-processes)
         (when (process-live-p process) (delete-process process)))
       (dolist (process ade-runtime-test--ghostel-processes)
         (when-let* ((buffer (process-buffer process)))
           (when (buffer-live-p buffer) (kill-buffer buffer))))
       (ade-core-reset)
       (setq ade-runtime--current nil
             ade-runtime-process-function nil
             ade-app-server-transport-factory nil
             ade-ghostel-exec-function nil))))

(ert-deftest ade-runtime-starts-one-local-owner-and-stops-only-it ()
  (ade-runtime-test--clean
   (let ((ade-runtime-process-function
          #'ade-runtime-test--process-factory))
     (should-not (ade-runtime-current))
     (let ((runtime (ade-runtime-start)))
       (should (ade-runtime-p runtime))
       (should (equal (ade-runtime-state runtime) 'running))
       (should (equal (ade-runtime-url runtime)
                      "ws://127.0.0.1:43123"))
       (should (ade-runtime-running-p runtime))
       (should (= ade-runtime-test--factory-count 1))
       (should (equal (plist-get (car ade-runtime-test--processes) :program)
                      "codex"))
       (should (equal (plist-get (car ade-runtime-test--processes) :args)
                      '("app-server" "--listen" "ws://127.0.0.1:0")))
       (should (plist-get (car ade-runtime-test--processes) :noquery))
       (should (eq runtime (ade-runtime-start))))
     (should (= ade-runtime-test--factory-count 1))
     (ade-runtime-stop)
     (should-not (ade-runtime-running-p))
     (should-not (ade-runtime-url (ade-runtime-current)))
     (should-not (plist-get (car ade-runtime-test--processes) :live)))))

(ert-deftest ade-runtime-rejects-nonlocal-and-times-out-finitely ()
  (ade-runtime-test--clean
   (let ((ade-runtime-process-function
          #'ade-runtime-test--nonlocal-process-factory)
         (error-seen nil))
     (should-error
      (ade-runtime-start nil (lambda (_runtime error) (setq error-seen error)))
      :type 'ade-runtime-nonlocal-error)
     (should error-seen)
     (should-not (ade-runtime-url (ade-runtime-current)))
     (should-not (plist-get (car ade-runtime-test--processes) :live)))
   (let ((ade-runtime-process-function
          #'ade-runtime-test--silent-process-factory)
         (ade-runtime-start-timeout 0)
         (error-seen nil))
     (should-error
      (ade-runtime-start nil (lambda (_runtime error) (setq error-seen error)))
      :type 'ade-runtime-timeout-error)
     (should error-seen)
     (should-not (ade-runtime-url (ade-runtime-current)))
     (should-not (plist-get (car ade-runtime-test--processes) :live)))))

(ert-deftest ade-runtime-process-exit-clears-endpoint-and-becomes-unknown ()
  (ade-runtime-test--clean
   (let* ((ade-runtime-process-function #'ade-runtime-test--process-factory)
          (runtime (ade-runtime-start))
          (process (car ade-runtime-test--processes)))
     (setf (plist-get process :live) nil)
     (funcall (plist-get process :on-exit) "exited")
     (should (eq (ade-runtime-state runtime) 'unknown))
     (should-not (ade-runtime-url runtime))
     (should-not (ade-runtime-running-p runtime)))))

(ert-deftest ade-runtime-stop-disconnects-owned-endpoint-agents-without-deleting ()
  (ade-runtime-test--clean
   (let* ((workspace (ade-runtime-test--workspace))
          (ade-runtime-process-function #'ade-runtime-test--process-factory)
          (runtime (ade-runtime-start))
          (agent (ade-agent-new
                  :id "runtime-stop-agent"
                  :workspace-uuid (ade-workspace-uuid workspace)
                  :thread-id "runtime-stop-thread"
                  :endpoint (ade-runtime-url runtime)
                  :state 'idle)))
     (setf (ade-agent-connection agent)
           (ade-app-server-create :url (ade-runtime-url runtime)))
     (ade-core-register-agent agent t)
     (cl-letf (((symbol-function 'ade-agent-disconnect)
                (lambda (selected intentional)
                  (should (eq selected agent))
                  (should intentional)
                  selected)))
       (ade-runtime-stop))
     (should (eq (ade-core-agent-by-id "runtime-stop-agent") agent))
     (should (eq (ade-agent-state agent) 'unknown))
     (should-not (ade-runtime-url runtime)))))

(ert-deftest ade-runtime-start-agent-registers-before-ghostel-with-one-reader ()
  (ade-runtime-test--clean
   (ade-runtime-test--with-wire
    (let* ((workspace (ade-runtime-test--workspace))
           (ade-runtime-process-function #'ade-runtime-test--process-factory)
           (ade-app-server-transport-factory #'ade-runtime-test--transport)
           (ade-ghostel-exec-function #'ade-runtime-test--ghostel-exec)
           (callback-agent nil)
           (error-seen nil)
           (agent
            (ade-runtime-start-agent
             :model "gpt-test"
             :callback (lambda (ready-agent) (setq callback-agent ready-agent))
             :errorback (lambda (_failed-agent error) (setq error-seen error)))))
      (should (ade-agent-p agent))
      (should (eq (ade-core-current-workspace) workspace))
      ;; The record exists as an object, but core registration waits for the
      ;; initialize response and thread/start result.
      (should-not (ade-core-agent-by-id (ade-agent-id agent)))
      (funcall (plist-get ade-runtime-test--transport :on-open)
               ade-runtime-test--transport)
      (should-not (ade-core-agent-by-id (ade-agent-id agent)))
      (ade-runtime-test--receive
       "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"userAgent\":\"fake\"}}")
      (should-not (ade-core-agent-by-id (ade-agent-id agent)))
      (ade-runtime-test--receive
       "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"thread\":{\"id\":\"runtime-thread\",\"model\":\"gpt-test\"}}}")
      (should (eq (ade-core-agent-by-id (ade-agent-id agent)) agent))
      (should (equal (ade-workspace-selected-agent-id workspace)
                     (ade-agent-id agent)))
      (should (eq callback-agent agent))
      (should-not error-seen)
      (should (= ade-runtime-test--factory-count 1))
      (should (process-live-p (ade-agent-process agent)))
      (let ((methods
             (delq nil
                   (mapcar
                    (lambda (text)
                      (let ((message (json-parse-string
                                      text :object-type 'alist)))
                        (alist-get 'method message)))
                    ade-runtime-test--sent))))
        (should (equal methods '("initialize" "initialized" "thread/start"))))))))

(ert-deftest ade-runtime-start-agent-retains-registered-record-on-tui-failure ()
  (ade-runtime-test--clean
   (ade-runtime-test--with-wire
    (let* ((workspace (ade-runtime-test--workspace))
           (ade-runtime-process-function #'ade-runtime-test--process-factory)
           (ade-app-server-transport-factory #'ade-runtime-test--transport)
           (ade-ghostel-exec-function #'ade-runtime-test--ghostel-exec)
           (ade-runtime-test--ghostel-fails t)
           (error-seen nil)
           (agent
            (ade-runtime-start-agent
             :callback (lambda (_ready-agent) (ert-fail "unexpected success"))
             :errorback (lambda (_failed-agent error) (setq error-seen error)))))
      (funcall (plist-get ade-runtime-test--transport :on-open)
               ade-runtime-test--transport)
      (ade-runtime-test--receive
       "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"userAgent\":\"fake\"}}")
      (ade-runtime-test--receive
       "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"thread\":{\"id\":\"runtime-thread-fail\"}}}")
      (should error-seen)
      (should (eq (ade-core-agent-by-id (ade-agent-id agent)) agent))
      (should (equal (ade-workspace-selected-agent-id workspace)
                     (ade-agent-id agent)))
      (should (equal (ade-agent-thread-id agent) "runtime-thread-fail"))))))

(provide 'ade-runtime-test)

;;; ade-runtime-test.el ends here
