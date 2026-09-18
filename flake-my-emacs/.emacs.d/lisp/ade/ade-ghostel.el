;;; ade-ghostel.el --- Non-destructive Ghostel process adapter -*- lexical-binding: t; -*-

;;; Commentary:

;; Ghostel hosts the official remote Codex TUI.  This adapter owns only the
;; process/buffer attachment and key transport; it never infers protocol
;; state from terminal prose and never changes the selected Agent.  The
;; App Server handshake remains the registration gate.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ade-agent)

(defgroup ade-ghostel nil
  "Ghostel process adapter for ADE Agents."
  :group 'ade)

(defcustom ade-ghostel-program "codex"
  "Codex executable used for the remote TUI."
  :type 'string
  :group 'ade-ghostel)

(defvar ade-ghostel-exec-function nil
  "Optional function `(BUFFER PROGRAM ARGS IDENTITY) -> process'.

The function is called in a `default-directory' dynamically bound to the
Agent's fixed root.  Its calling convention mirrors Ghostel 0.52's
`ghostel-exec'; the adapter owns the process sentinel and exit callback.")

(defvar ade-ghostel-send-key-function nil
  "Optional function `(BUFFER KEY MODIFIERS)'.

MODIFIERS is nil or Ghostel's comma-separated modifier string.")

(define-error 'ade-ghostel-error "ADE Ghostel error" 'ade-error)

(defun ade-ghostel-command (url thread-id)
  "Return the fixed-root remote TUI command for URL and THREAD-ID."
  (unless (and (stringp url) (not (string-empty-p url)))
    (signal 'ade-ghostel-error (list "App Server URL is empty" url)))
  (unless (and (stringp thread-id) (not (string-empty-p thread-id)))
    (signal 'ade-ghostel-error (list "Thread ID is empty" thread-id)))
  (list ade-ghostel-program "--remote" url "resume" thread-id))

(defun ade-ghostel--default-exec (buffer program args identity)
  "Execute PROGRAM with ARGS in BUFFER through Ghostel.

The caller binds `default-directory' to the fixed Agent root.  Keeping the
program and argv separate is important: the remote URL and thread id must not
be reparsed by a shell or a terminal command string."
  (unless (require 'ghostel nil t)
    (signal 'ade-ghostel-error
            (list "ghostel.el is not available" program args)))
  (unless (fboundp 'ghostel-exec)
    (signal 'ade-ghostel-error
            (list "ghostel-exec is not available" program args)))
  (ghostel-exec buffer program args identity))

(defun ade-ghostel--exec (buffer program args identity)
  "Call the injected or installed Ghostel executor."
  (funcall (or ade-ghostel-exec-function #'ade-ghostel--default-exec)
           buffer program args identity))

(defun ade-ghostel--send-key-default (buffer key modifiers)
  "Send KEY and MODIFIERS through Ghostel's semantic key API."
  (unless (require 'ghostel nil t)
    (signal 'ade-ghostel-error (list "ghostel.el is not available")))
  (unless (fboundp 'ghostel-send-key)
    (signal 'ade-ghostel-error (list "ghostel-send-key is not available")))
  (with-current-buffer buffer
    (ghostel-send-key key modifiers)))

(defun ade-ghostel--modifier-string (modifiers)
  "Normalize MODIFIERS to Ghostel's optional comma-separated string."
  (cond
   ((null modifiers) nil)
   ((stringp modifiers) modifiers)
   ((listp modifiers)
    (string-join (mapcar (lambda (modifier) (format "%s" modifier))
                         modifiers)
                 ","))
   (t (format "%s" modifiers))))

(defun ade-ghostel-send-key (agent key &rest modifiers)
  "Send semantic KEY and MODIFIERS to AGENT's Ghostel buffer."
  (let ((buffer (ade-agent-buffer agent)))
    (unless (buffer-live-p buffer)
      (signal 'ade-ghostel-error (list "Agent has no Ghostel buffer" agent)))
    (let ((modifier-string (ade-ghostel--modifier-string modifiers)))
      (if ade-ghostel-send-key-function
          (funcall ade-ghostel-send-key-function
                   buffer key modifier-string)
        (ade-ghostel--send-key-default buffer key modifier-string)))))

(defun ade-ghostel-send-string (agent text)
  "Send TEXT to AGENT through Ghostel's semantic string API."
  (let ((buffer (ade-agent-buffer agent)))
    (unless (buffer-live-p buffer)
      (signal 'ade-ghostel-error (list "Agent has no Ghostel buffer" agent)))
    (unless (require 'ghostel nil t)
      (signal 'ade-ghostel-error (list "ghostel.el is not available")))
    (unless (fboundp 'ghostel-send-string)
      (signal 'ade-ghostel-error (list "ghostel-send-string is not available")))
    (with-current-buffer buffer
      (ghostel-send-string text))))

(defun ade-ghostel-send-control-c (agent)
  "Send semantic Ctrl-C to AGENT, never raw ASCII SIGINT."
  (ade-ghostel-send-key agent "c" "ctrl"))

(defun ade-ghostel-start (agent &optional url root callback)
  "Launch AGENT's remote TUI in fixed ROOT and connect its App Server.

The Agent is registered only from the post-handshake callback.  CALLBACK is
invoked with AGENT after that gate succeeds.  Existing thread IDs reconnect
the same Agent; no new Agent is made for a TUI restart."
  (unless (ade-agent-p agent)
    (signal 'ade-ghostel-error (list "Not an ADE Agent" agent)))
  (let* ((endpoint (or url (ade-agent--metadata-get agent :endpoint)))
         (fixed-root (or root (ade-agent--metadata-get agent :root)))
         (thread-id (ade-agent-thread-id agent)))
    (unless (and (stringp fixed-root) (file-directory-p fixed-root))
      (signal 'ade-ghostel-error
              (list "Ghostel root is not a directory" fixed-root)))
    (unless thread-id
      (signal 'ade-ghostel-error
              (list "A remote TUI resume requires a thread id")))
    (ade-agent--metadata-put agent :endpoint endpoint)
    (ade-agent--metadata-put agent :root fixed-root)
    (let* ((existing-connection (ade-agent-connection agent))
           (already-connected
            (and existing-connection
                 (ade-app-server-connected-p existing-connection)))
           (command (ade-ghostel-command endpoint thread-id))
           (program (car command))
           (args (cdr command))
           (buffer (generate-new-buffer
                    (format "*ade-ghostel-%s*" (ade-agent-id agent))))
           (identity `((kind . ade-codex)
                       (agent-id . ,(ade-agent-id agent))
                       (thread-id . ,thread-id)
                       (command . ,(copy-sequence command))))
           (process
            (condition-case err
                (let ((default-directory
                        (file-name-as-directory (expand-file-name fixed-root))))
                  (ade-ghostel--exec buffer program args identity))
              (error
               (when (buffer-live-p buffer) (kill-buffer buffer))
               (signal (car err) (cdr err)))))
           (process-buffer (and (processp process)
                                (process-buffer process))))
      (unless (processp process)
        (when (buffer-live-p buffer) (kill-buffer buffer))
        (signal 'ade-ghostel-error
                (list "ghostel-exec did not return a process" process)))
      ;; `ghostel-exec' installs Ghostel's renderer sentinel.  Chain our
      ;; non-destructive Agent record update around it instead of replacing it.
      (let ((previous (process-sentinel process)))
        (set-process-sentinel
         process
         (lambda (child event)
           (ade-agent-process-exited agent event)
           (when previous (funcall previous child event)))))
      (unless (buffer-live-p process-buffer)
        (setq process-buffer buffer))
      (ade-agent-mark-process agent process process-buffer)
      ;; A runtime-started Agent is already handshaken and registered before
      ;; this function is called.  Reusing that connection is important:
      ;; calling `ade-agent-connect' here would create a second websocket
      ;; reader for the same Agent.  An already-connected but unregistered
      ;; record is registered at this same handshake boundary.
      (if already-connected
          (progn
            (unless (ade-core-agent-by-id (ade-agent-id agent))
              (ade-agent-register-after-handshake agent nil))
            (when callback (funcall callback agent)))
        ;; This callback is reached only after initialize/initialized and safe
        ;; resume reconciliation have completed.
        (ade-agent-connect
         agent
         (lambda (ready-agent)
           (ade-agent-register-after-handshake ready-agent nil)
           (when callback (funcall callback ready-agent)))))
      agent)))

(defalias 'ade-ghostel-launch #'ade-ghostel-start)

(defun ade-ghostel-reattach (agent &optional callback)
  "Reattach AGENT's existing thread to a new Ghostel TUI, unselected."
  (ade-ghostel-start agent nil nil callback))

(defun ade-ghostel-detach (agent)
  "Detach AGENT without killing its Ghostel process or deleting its record."
  (ade-agent-detach agent))

(provide 'ade-ghostel)

;;; ade-ghostel.el ends here
