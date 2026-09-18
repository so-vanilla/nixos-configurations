;;; ade.el --- ADE public initialization and explicit buffer attach -*- lexical-binding: t; -*-

;;; Commentary:

;; This is the public composition root for the session-local ADE modules.  A
;; `require' is intentionally inert: it installs no startup UI and does not
;; scan or attach arbitrary buffers.  `ade-init' is the explicit user action
;; that initializes the current Perspective and displays its Workspace Prompt.

;;; Code:

(require 'ade-core)
(require 'ade-perspective)
(require 'ade-workspace)
(require 'ade-state)
(require 'ade-app-server)
(require 'ade-agent)
(require 'ade-request)
(require 'ade-send)
(require 'ade-model)
(require 'ade-ghostel)
(require 'ade-side)
(require 'ade-runtime)
(require 'ade-platform)
(require 'ade-prompt)
(require 'ade-sidebar)

(defgroup ade-entry nil
  "Public ADE initialization and integration commands."
  :group 'ade)

(defvar ade--initialized-p nil
  "Non-nil after explicit `ade-init' has completed in this Emacs session.")

(defvar ade--attach-hook-installed-p nil
  "Non-nil after the explicit C-x b Ghostel attach hook is installed.")

(defvar-local ade-ghostel-agent-id nil
  "Optional explicit stable ADE Agent ID carried by a Ghostel buffer.

Ghostel/TUI buffer names and process IDs are not identity.  A buffer adapter
may set this marker when it has a protocol-backed identity; absent that marker
ADE refuses to attach the buffer automatically.")

(defvar-local ade-ghostel-thread-id nil
  "Optional protocol thread ID carried by a Ghostel buffer for diagnostics.")

(defun ade-current-selected-agent ()
  "Return the current Workspace's selected Agent, or signal a user error."
  (let* ((workspace (ade-core-current-workspace))
         (agent-id (and workspace
                        (ade-workspace-selected-agent-id workspace)))
         (agent (and agent-id (ade-core-agent-by-id agent-id))))
    (unless workspace
      (user-error "ADE Workspace is not initialized"))
    (unless agent
      (user-error "Current ADE Workspace has no selected Agent"))
    agent))

(defun ade-start-agent ()
  "Explicitly create and start one Agent in the current Workspace.

The owned loopback App Server is started on demand.  This command returns the
new record immediately; readiness or failure is reported asynchronously and
does not open or replace the user's current buffer."
  (interactive)
  (let ((agent
         (ade-runtime-start-agent
          :callback
          (lambda (ready-agent)
            (ade-sidebar-refresh)
            (message "ADE Agent %s is ready; use M-x ade-show-selected-agent"
                     (ade-agent-id ready-agent)))
          :errorback
          (lambda (failed-agent error)
            (ade-sidebar-refresh)
            (message "ADE Agent %s failed: %s"
                     (ade-agent-id failed-agent)
                     (error-message-string error))))))
    (message "ADE Agent %s is starting" (ade-agent-id agent))
    agent))

(defun ade-show-selected-agent ()
  "Display the selected Agent's live Ghostel buffer explicitly."
  (interactive)
  (let* ((agent (ade-current-selected-agent))
         (buffer (ade-agent-buffer agent)))
    (unless (buffer-live-p buffer)
      (user-error "Selected Agent has no live Ghostel buffer"))
    (pop-to-buffer buffer)
    buffer))

(defun ade--json-get (object key)
  "Return KEY from protocol OBJECT represented as an alist or plist."
  (let* ((name (if (symbolp key) (symbol-name key) key))
         (symbol (and (stringp name) (intern name)))
         (keyword (and (stringp name) (intern (concat ":" name)))))
    (and (listp object)
         (or (alist-get symbol object nil nil #'equal)
             (alist-get name object nil nil #'equal)
             (plist-get object keyword)
             (plist-get object symbol)))))

(defun ade--read-reasoning-effort (model)
  "Read an optional reasoning effort advertised by MODEL."
  (let* ((options (ade--json-get model 'supportedReasoningEfforts))
         (values (delq nil
                       (mapcar (lambda (option)
                                 (ade--json-get option 'reasoningEffort))
                               options))))
    (when values
      (let ((choice
             (completing-read
              "Reasoning effort: "
              (cons "model default" values) nil t nil nil "model default")))
        (unless (equal choice "model default") choice)))))

(defun ade--apply-model-choice (agent models)
  "Read and apply one model from MODELS to AGENT."
  (let* ((default (propertize "configured default / clear override"
                              'ade-model-default t))
         (candidates
          (cons
           default
           (mapcar
            (lambda (model)
              (let ((id (or (ade--json-get model 'model)
                            (ade--json-get model 'id)))
                    (name (or (ade--json-get model 'displayName)
                              (ade--json-get model 'model)
                              (ade--json-get model 'id))))
                (propertize (format "%s  [%s]" name id)
                            'ade-model-record model)))
            models)))
         (choice (completing-read "ADE model: " candidates nil t))
         (model-record (get-text-property 0 'ade-model-record choice))
         (default-p (get-text-property 0 'ade-model-default choice))
         (model (and model-record
                     (or (ade--json-get model-record 'model)
                         (ade--json-get model-record 'id))))
         (effort (and model-record
                      (ade--read-reasoning-effort model-record))))
    (unless (or default-p model-record)
      (user-error "Unknown ADE model selection"))
    (ade-model-update
     agent model effort
     (lambda (_result updated-agent)
       (ade-sidebar-refresh)
       (message "ADE Agent %s model override: %s%s"
                (ade-agent-id updated-agent)
                (or model "configured default")
                (if effort (format " (%s)" effort) "")))
     (lambda (error _failed-agent)
       (message "ADE model update failed: %s" (error-message-string error))))))

(defun ade-select-model ()
  "Refresh App Server models and select a future-turn model/effort."
  (interactive)
  (let* ((agent (ade-current-selected-agent))
         (connection (ade-agent-connection agent)))
    (unless (and connection (ade-app-server-connected-p connection))
      (user-error "Selected Agent is disconnected"))
    (ade-model-list
     connection
     (lambda (models _connection)
       (condition-case nil
           (ade--apply-model-choice agent models)
         (quit (message "ADE model selection cancelled"))))
     (lambda (error _connection)
       (message "ADE model discovery failed: %s" (error-message-string error)))
     t nil)))

(defun ade--choose-pending-request (agent)
  "Read one answerable pending request belonging to AGENT."
  (let ((requests
         (cl-remove-if-not #'ade-request-pending-p
                           (ade-request-pending-for-agent agent))))
    (cond
     ((null requests) (user-error "Selected Agent has no pending request"))
     ((null (cdr requests)) (car requests))
     (t
      (let* ((candidates
              (mapcar
               (lambda (request)
                 (propertize
                  (format "%s  %s" (ade-request-kind request)
                          (ade-request-id request))
                  'ade-request-record request))
               requests))
             (choice (completing-read "ADE request: " candidates nil t)))
        (or (get-text-property 0 'ade-request-record choice)
            (user-error "Unknown ADE request selection")))))))

(defun ade--read-json-object (prompt &optional initial)
  "Read one JSON object using PROMPT and INITIAL text."
  (let ((text (read-from-minibuffer prompt (or initial "{}"))))
    (condition-case error
        (json-parse-string text :object-type 'alist :array-type 'vector
                           :null-object nil :false-object :json-false)
      (error (user-error "Invalid JSON response: %s"
                         (error-message-string error))))))

(defun ade--read-approval-response (request)
  "Read one structured approval response for REQUEST."
  (let ((choices (ade-request-choices request)))
    (if (null choices)
        (ade--read-json-object "Structured approval response (JSON): ")
      (let* ((candidates
              (mapcar
               (lambda (choice)
                 (propertize (or (plist-get choice :label)
                                 (format "%s" (plist-get choice :value)))
                             'ade-decision-value
                             (plist-get choice :value)))
               choices))
             (selected (completing-read "ADE decision: " candidates nil t)))
        (list (cons 'decision
                    (get-text-property 0 'ade-decision-value selected)))))))

(defun ade--read-tool-user-input-response (request)
  "Read all structured user-input questions in REQUEST."
  (let ((questions (ade--json-get (ade-request-params request) 'questions))
        answers)
    (unless questions
      (user-error "User-input request has no questions"))
    (dolist (question questions)
      (let* ((id (ade--json-get question 'id))
             (prompt (or (ade--json-get question 'question) "Answer"))
             (options (ade--json-get question 'options))
             (labels (delq nil
                           (mapcar (lambda (option)
                                     (or (ade--json-get option 'label)
                                         (ade--json-get option 'value)))
                                   options)))
             (answer (completing-read (format "%s: " prompt)
                                      labels nil nil)))
        (unless (and (stringp id) (not (string-empty-p id)))
          (user-error "User-input question has no stable id"))
        ;; `json-serialize' requires symbol object keys.  Interning preserves
        ;; the exact question id as its emitted JSON member name.
        (push (cons (intern id)
                    (list (cons 'answers (vector answer))))
              answers)))
    (list (cons 'answers (nreverse answers)))))

(defun ade--read-elicitation-response (request)
  "Read an MCP elicitation action and optional structured content."
  (let ((action (completing-read "Elicitation action: "
                                 '("accept" "decline" "cancel") nil t)))
    (if (equal action "accept")
        (list (cons 'action action)
              (cons 'content
                    (ade--read-json-object "Elicitation content (JSON): ")))
      (list (cons 'action action)))))

(defun ade--read-request-response (request)
  "Read a protocol-shaped response for REQUEST."
  (let ((method (downcase (format "%s" (ade-request-method request)))))
    (cond
     ((string-match-p "item/tool/requestuserinput" method)
      (ade--read-tool-user-input-response request))
     ((string-match-p "mcpserver/elicitation/request" method)
      (ade--read-elicitation-response request))
     ((eq (ade-request-kind request) 'approval)
      (ade--read-approval-response request))
     (t
      (ade--read-json-object "Structured request response (JSON): ")))))

(defun ade-answer-request ()
  "Explicitly answer one pending request for the selected Agent.

Incoming requests never call this command automatically.  Cancelling any
minibuffer leaves the request pending and does not change Workspace, Agent,
Prompt, focus, or window state."
  (interactive)
  (let* ((agent (ade-current-selected-agent))
         (request (ade--choose-pending-request agent))
         (response (ade--read-request-response request)))
    (ade-request-respond
     request response
     (lambda (_request)
       (ade-sidebar-refresh)
       (message "ADE request %s response sent" (ade-request-id request)))
     (lambda (_request error)
       (ade-sidebar-refresh)
       (message "ADE request %s response failed: %s"
                (ade-request-id request) (error-message-string error))))))

(defun ade-create-side ()
  "Explicitly create a verified ephemeral side for the selected Agent."
  (interactive)
  (let ((agent (ade-current-selected-agent)))
    (ade-side-create
     agent
     (lambda (side)
       (message "ADE side %s is ready" (ade-side-thread-id side)))
     (lambda (error _agent)
       (message "ADE side creation failed: %s" (error-message-string error))))))

(defun ade-toggle-agent-side-view ()
  "Explicitly ask the selected Codex TUI to toggle its side view.

The TUI-created side remains unknown unless ADE can verify its protocol
identity; this command therefore grants no side send/close authority."
  (interactive)
  (ade-side-toggle-tui (ade-current-selected-agent)))

(defun ade-close-side ()
  "Explicitly forget the selected Agent's verified ephemeral side."
  (interactive)
  (let ((side (ade-side-close (ade-current-selected-agent))))
    (message "ADE side %s closed locally" (ade-side-thread-id side))
    side))

(defun ade--ghostel-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is a recognized Ghostel buffer.

Only a Ghostel mode or an explicitly provided Ghostel predicate qualifies.
Generic terminal/comint buffers and buffer-name heuristics are rejected."
  (with-current-buffer (or buffer (current-buffer))
    (or (derived-mode-p 'ghostel-mode 'ghostel-vt-mode)
        (and (fboundp 'ghostel-buffer-p)
             (condition-case nil
                 (ghostel-buffer-p (current-buffer))
               (error nil))))))

(defun ade--agent-for-buffer (buffer)
  "Return the registered Agent whose Ghostel buffer is BUFFER, or nil."
  (cl-loop for workspace in (ade-core-workspaces)
           thereis
           (cl-loop for agent-id in (ade-workspace-agent-ids workspace)
                    for agent = (ade-core-agent-by-id agent-id)
                    when (and agent (eq (ade-agent-buffer agent) buffer))
                    return agent)))

(defun ade--explicit-buffer-agent ()
  "Return an Agent explicitly identified by the current Ghostel buffer."
  (or (ade--agent-for-buffer (current-buffer))
      (and ade-ghostel-agent-id
           (ade-core-agent-by-id ade-ghostel-agent-id))))

(defun ade-attach-current-buffer ()
  "Explicitly attach the selected Ghostel buffer to the current Workspace.

This command is also called only after the default `switch-to-buffer' command
selects a recognized Ghostel buffer.  It never guesses identity from a name
or PID.  A previously detached, explicitly identified Agent is reattached and
selected; an already registered Agent is selected without reconnecting or
focusing its process."
  (interactive)
  (unless (ade--ghostel-buffer-p)
    (user-error "Current buffer is not a recognized Ghostel buffer"))
  (let ((workspace (ade-core-current-workspace)))
    (unless workspace
      (user-error "ADE Workspace is not initialized; attach skipped"))
    (let ((agent (ade--explicit-buffer-agent)))
      (if (not agent)
          (progn
            (message "ADE: Ghostel identity is unavailable; attach skipped")
            nil)
        (let ((agent-workspace (ade-agent-workspace-uuid agent))
              (attached-p nil))
          (cond
           ((equal agent-workspace (ade-workspace-uuid workspace))
            (ade-core-select-agent (ade-workspace-uuid workspace)
                                   (ade-agent-id agent))
            (setq attached-p t))
           ((ade-agent-detached-p agent)
            ;; Reattach is explicit and selected.  The existing connection and
            ;; process remain untouched; reconnect is a separate operation.
            (ade-agent-reattach agent (ade-workspace-uuid workspace) nil t)
            (setq attached-p t))
           (t
            (message
             "ADE: Ghostel Agent belongs to another Workspace; attach skipped")))
          (when attached-p
            (ade-sidebar-refresh)
            agent))))))

(defun ade--maybe-attach-after-switch-to-buffer ()
  "Attach only after an explicit default `switch-to-buffer' command."
  (when (and (eq this-command 'switch-to-buffer)
             (ade--ghostel-buffer-p))
    (condition-case err
        (ade-attach-current-buffer)
      (error
       (message "ADE: explicit Ghostel attach skipped: %s"
                (error-message-string err))))))

(defun ade--install-explicit-attach-hook ()
  "Install the post-command hook used for explicit C-x b Ghostel attach."
  (unless ade--attach-hook-installed-p
    (setq ade--attach-hook-installed-p t)
    (add-hook 'post-command-hook #'ade--maybe-attach-after-switch-to-buffer)))

(defun ade-init ()
  "Initialize the current Workspace and display its Prompt.

Initialization is idempotent: Workspace, Agent, connection, and Prompt
records already owned by the current Perspective are preserved.  This command
does not open the global sidebar, start an Agent, scan buffers, or attach a
Ghostel process except for the later explicit C-x b path."
  (interactive)
  (let ((workspace (ade-workspace-init)))
    (setq ade--initialized-p t)
    (ade--install-explicit-attach-hook)
    (ade-prompt-display-current)
    workspace))

(defalias 'ade-initialize #'ade-init)

(provide 'ade)

;;; ade.el ends here
