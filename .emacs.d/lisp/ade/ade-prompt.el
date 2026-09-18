;;; ade-prompt.el --- Workspace-owned ADE Prompt buffers -*- lexical-binding: t; -*-

;;; Commentary:

;; A Prompt is a file-less, derived Org buffer owned by exactly one ADE
;; Workspace.  The owner UUID is buffer-local and is never inferred from the
;; currently selected Perspective at send time.  This keeps an old Prompt
;; view useful for reading while making a Workspace mismatch a safe no-send
;; boundary.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'subr-x)
(require 'ade-core)
(require 'ade-workspace)

(defgroup ade-prompt nil
  "Workspace-owned ADE Prompt buffers."
  :group 'ade)

(defcustom ade-prompt-buffer-prefix "*ADE Prompt"
  "Prefix used for file-less ADE Prompt buffer names."
  :type 'string
  :group 'ade-prompt)

(defcustom ade-prompt-takeover-confirm-function nil
  "Optional confirmation function for an idle unknown-origin Agent.

The function receives the selected Agent and returns non-nil only after an
explicit human decision.  When nil, an interactive command asks with
`y-or-n-p'; noninteractive callers remain no-send."
  :type '(choice (const :tag "Ask with y-or-n-p" nil) function)
  :group 'ade-prompt)

(defcustom ade-prompt-agent-consult-function nil
  "Optional chooser used by the one-prefix Prompt Agent selection.

The function receives a list of registered Agent records and must return one
of those records, or nil when selection is cancelled.  Returning records
rather than parsing display strings keeps protocol identity out of the
completion UI boundary."
  :type '(choice (const :tag "Use consult" nil) function)
  :group 'ade-prompt)

(defvar-local ade-prompt-owner-uuid nil
  "Immutable ADE Workspace UUID owning the current Prompt buffer.

This is buffer-local state.  It is intentionally not replaced merely because
the user switches to another Workspace while this buffer remains visible.")

(defvar-local ade-prompt-owner-name nil
  "Cached human-facing owner name for the current Prompt header.")

(defvar-local ade-prompt-warning nil
  "Non-destructive warning shown in the current Prompt header, or nil.")

(defvar ade-prompt--buffers (make-hash-table :test #'equal)
  "Session-local map from Workspace UUID to its sole Prompt buffer.")

(defun ade-prompt--workspace (value)
  "Resolve VALUE to an ADE Workspace, or signal when it is absent.

VALUE may be a Workspace record, UUID, human-facing name, or nil for the
current Workspace.  No Perspective operation is performed here."
  (cond
   ((ade-workspace-p value) value)
   ((null value) (or (ade-core-current-workspace)
                     (signal 'ade-no-current-workspace-error nil)))
   ((and (stringp value) (ade-core-workspace-by-uuid value)))
   ((and (stringp value) (ade-core-workspace-by-name value)))
   (t (signal 'ade-not-found-error (list "Workspace" value)))))

(defun ade-prompt--buffer-name (workspace)
  "Return the display buffer name for WORKSPACE."
  (format "%s: %s*" ade-prompt-buffer-prefix
          (ade-workspace-name workspace)))

(defun ade-prompt--owner-workspace ()
  "Return the Workspace owned by the current Prompt buffer, or nil."
  (and ade-prompt-owner-uuid
       (ade-core-workspace-by-uuid ade-prompt-owner-uuid)))

(defun ade-prompt--header-line ()
  "Return a dynamic header line for the current Prompt buffer."
  (let* ((workspace (ade-prompt--owner-workspace))
         (name (or (and workspace (ade-workspace-name workspace))
                   ade-prompt-owner-name
                   "unknown"))
         (current-p (and workspace
                         (equal ade-prompt-owner-uuid
                                (ade-core-current-uuid))))
         (status (if current-p "" "  [view only: another Workspace is current]"))
         (warning (if ade-prompt-warning
                      (format "  [warning: %s]" ade-prompt-warning)
                    "")))
    (format " ADE Prompt · %s%s%s" name status warning)))

(defun ade-prompt--warn (format-string &rest args)
  "Store and display a non-destructive warning from FORMAT-STRING and ARGS."
  (setq-local ade-prompt-warning (apply #'format format-string args))
  (message "ADE Prompt: %s" ade-prompt-warning)
  nil)

(defun ade-prompt--clear-warning ()
  "Clear the current Prompt warning and refresh its header."
  (setq-local ade-prompt-warning nil)
  (force-mode-line-update t))

(defun ade-prompt--killed ()
  "Remove the current Prompt from the session-local owner map."
  (when (and ade-prompt-owner-uuid
             (eq (gethash ade-prompt-owner-uuid ade-prompt--buffers)
                 (current-buffer)))
    (remhash ade-prompt-owner-uuid ade-prompt--buffers)))

(define-derived-mode ade-prompt-mode org-mode "ADE-Prompt"
  "Major mode for one Workspace-owned, file-less ADE Prompt.

The mode does not enable SKK automatically.  On WSL, call
`ade-prompt-enable-skk' explicitly when Japanese input is wanted."
  (setq-local buffer-file-name nil)
  (setq-local buffer-offer-save nil)
  (setq-local ade-prompt-warning nil)
  (setq-local header-line-format
              '(" " (:eval (ade-prompt--header-line))))
  (use-local-map (copy-keymap (current-local-map)))
  (define-key (current-local-map) (kbd "C-c '") #'ade-prompt-send)
  (define-key (current-local-map) (kbd "C-c \"") #'ade-prompt-send-side)
  (add-hook 'kill-buffer-hook #'ade-prompt--killed nil t))

(defun ade-prompt-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is an ADE Prompt buffer."
  (with-current-buffer (or buffer (current-buffer))
    (and (derived-mode-p 'ade-prompt-mode)
         (stringp ade-prompt-owner-uuid))))

(defun ade-prompt-for-workspace (&optional value)
  "Return the sole file-less Prompt buffer for Workspace VALUE.

The buffer is created only on explicit use.  Repeated calls return the same
buffer, preserving its text, owner UUID, and local editing state."
  (let* ((workspace (ade-prompt--workspace value))
         (uuid (ade-workspace-uuid workspace))
         (buffer (gethash uuid ade-prompt--buffers)))
    (if (buffer-live-p buffer)
        (progn
          (with-current-buffer buffer
            (setq-local ade-prompt-owner-name (ade-workspace-name workspace))
            (rename-buffer (ade-prompt--buffer-name workspace) t)
            (force-mode-line-update t))
          buffer)
      (setq buffer (generate-new-buffer (ade-prompt--buffer-name workspace)))
      (with-current-buffer buffer
        (ade-prompt-mode)
        (setq-local ade-prompt-owner-uuid uuid
                    ade-prompt-owner-name (ade-workspace-name workspace)
                    default-directory (file-name-as-directory
                                       (ade-workspace-root workspace))))
      (puthash uuid buffer ade-prompt--buffers)
      buffer)))

(defun ade-prompt-owner-workspace (&optional buffer)
  "Return the Workspace owning BUFFER, or nil for a non-Prompt buffer."
  (with-current-buffer (or buffer (current-buffer))
    (and (ade-prompt-buffer-p)
         (ade-prompt--owner-workspace))))

(defun ade-prompt-current-workspace-p (&optional buffer)
  "Return non-nil when BUFFER's owner is the current Workspace."
  (with-current-buffer (or buffer (current-buffer))
    (and (ade-prompt-buffer-p)
         (equal ade-prompt-owner-uuid (ade-core-current-uuid)))))

(defun ade-prompt-display-current ()
  "Display and return the current Workspace's Prompt buffer.

This is an explicit display helper; requiring ADE or switching Workspaces does
not call it.  It never creates a Prompt for any other Workspace."
  (interactive)
  (let ((buffer (ade-prompt-for-workspace)))
    (pop-to-buffer buffer)
    buffer))

(defalias 'ade-prompt-show-current #'ade-prompt-display-current)

(defun ade-prompt--selected-agent ()
  "Return the selected Agent for the current Prompt owner, or nil with warning."
  (let ((workspace (ade-prompt-owner-workspace)))
    (cond
     ((null workspace)
      (ade-prompt--warn "owning Workspace no longer exists; send blocked"))
     ((null (ade-workspace-selected-agent-id workspace))
      (ade-prompt--warn "no selected Agent; send blocked"))
     (t
      (or (ade-core-agent-by-id
           (ade-workspace-selected-agent-id workspace))
          (ade-prompt--warn "selected Agent is unavailable; send blocked"))))))

(defun ade-prompt--text ()
  "Return the entire current Prompt buffer without text properties."
  (buffer-substring-no-properties (point-min) (point-max)))

(defun ade-prompt--assert-send-context ()
  "Return selected Agent when current Prompt ownership permits sending."
  (unless (ade-prompt-buffer-p)
    (user-error "This buffer is not an ADE Prompt"))
  (if (not (ade-prompt-current-workspace-p))
      (ade-prompt--warn
       "Prompt belongs to another current Workspace; send blocked")
    (ade-prompt--selected-agent)))

(defun ade-prompt--confirm-takeover (agent)
  "Return non-nil only after an explicit takeover decision for AGENT."
  (cond
   (ade-prompt-takeover-confirm-function
    (funcall ade-prompt-takeover-confirm-function agent))
   ((called-interactively-p 'interactive)
    (message "ADE Prompt: selected Agent %s is idle, origin unknown"
             (ade-agent-id agent))
    (y-or-n-p
     (format "Take over Agent %s (idle, origin unknown) for ADE? "
             (ade-agent-id agent))))
   (t nil)))

(defun ade-prompt--callback-in-buffer (buffer function)
  "Return a callback invoking FUNCTION in live Prompt BUFFER.

Asynchronous App Server replies must never erase whichever buffer happens to
be selected when the reply arrives."
  (lambda (&rest args)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (apply function args)))))

(defun ade-prompt--clear-on-accepted-send (&rest args)
  "Clear Prompt text when an accepted-send SNAPSHOT appears in ARGS.

`ade-send-turn' passes AGENT, SNAPSHOT, and RESULT on success, while its
failure path passes AGENT, nil, and ERROR.  Requiring a non-nil snapshot keeps
failed sends non-destructive."
  (let ((snapshot (nth 1 args))
        (error-object (nth 2 args)))
    (if (and snapshot
             (or (not (fboundp 'ade-send-snapshot-p))
                 (ade-send-snapshot-p snapshot)))
        (progn
          (let ((inhibit-read-only t))
            (erase-buffer))
          (ade-prompt--clear-warning)
          t)
      (when error-object
        (ade-prompt--warn "send failed; Prompt retained: %s"
                          (error-message-string error-object))))))

(defun ade-prompt--clear-on-accepted-steer (&rest _args)
  "Clear Prompt after the steer protocol's success callback."
  (let ((inhibit-read-only t))
    (erase-buffer))
  (ade-prompt--clear-warning)
  t)

(defun ade-prompt--steer-error (_agent error)
  "Warn about asynchronous steer ERROR while retaining Prompt text."
  (ade-prompt--warn "steer failed; Prompt retained: %s"
                    (error-message-string error)))

(defun ade-prompt--call-steer
    (agent text expected success error)
  "Call the steer adapter with separate SUCCESS and ERROR callbacks.

The five-argument form is the current protocol boundary.  A four-argument
fallback keeps this UI loadable while an older protocol adapter is present;
that fallback is only for synchronous/test compatibility and cannot erase
text from its error path because the current adapter uses the five-argument
contract."
  (condition-case err
      (funcall #'ade-send-steer agent text expected success error)
    (wrong-number-of-arguments
     (funcall #'ade-send-steer
              agent text expected
              (lambda (callback-agent result)
                (if (ade-prompt--error-value-p result)
                    (funcall error callback-agent result)
                  (funcall success callback-agent result)))))))

(defun ade-prompt--error-value-p (value)
  "Return non-nil when VALUE has the shape of an App Server error object."
  (or (and (listp value)
           (or (assoc 'code value)
               (assoc "code" value)
               (plist-member value :code)
               (plist-member value :error)))
      (and (consp value) (eq (car value) 'error))))

(defun ade-prompt--send-main (agent)
  "Send or steer the current Prompt through AGENT's main thread.

The operation is state-driven: idle ADE turns start, working ADE turns are
steered, and blocked/done/unknown or non-ADE origins remain monitor-only.  An
idle unknown-origin Agent can cross the boundary only after explicit
takeover confirmation."
  (let ((text (ade-prompt--text))
        (state (ade-agent-state agent))
        (origin (ade-agent-turn-origin agent))
        (buffer (current-buffer)))
    (cond
     ((eq state 'idle)
      (cond
       ((eq origin 'ade)
        (if (not (fboundp 'ade-send-turn))
            (ade-prompt--warn "send protocol is unavailable; send blocked")
          (condition-case err
              (progn
                (ade-send-turn
                 agent text
                 (ade-prompt--callback-in-buffer
                  buffer #'ade-prompt--clear-on-accepted-send))
                t)
            (error
             (ade-prompt--warn "send failed; Prompt retained: %s"
                               (error-message-string err))))))
       ((eq origin 'unknown)
        (if (not (ade-prompt--confirm-takeover agent))
            (ade-prompt--warn
             "unknown-origin Agent requires explicit takeover; send blocked")
          (if (not (fboundp 'ade-send-turn))
              (ade-prompt--warn "send protocol is unavailable; send blocked")
            (condition-case err
                (progn
                  (ade-send-turn
                   agent text
                   (ade-prompt--callback-in-buffer
                    buffer #'ade-prompt--clear-on-accepted-send)
                   :takeover t)
                  t)
              (error
               (ade-prompt--warn "takeover/send failed; Prompt retained: %s"
                                 (error-message-string err)))))))
       (t
        (ade-prompt--warn
         "idle Agent origin is %s; Prompt send is monitor-only"
         (or origin 'unknown)))))
     ((and (eq state 'working) (eq origin 'ade))
      (if (not (fboundp 'ade-send-steer))
          (ade-prompt--warn "steer protocol is unavailable; send blocked")
        (condition-case err
            (progn
              (ade-prompt--call-steer
               agent text
               (and (fboundp 'ade-agent-current-turn-id)
                    (ade-agent-current-turn-id agent))
               (ade-prompt--callback-in-buffer
                buffer #'ade-prompt--clear-on-accepted-steer)
               (ade-prompt--callback-in-buffer
                buffer #'ade-prompt--steer-error))
              t)
          (error
           (ade-prompt--warn "steer failed; Prompt retained: %s"
                             (error-message-string err))))))
     (t
      (ade-prompt--warn
       "Agent is %s (origin %s); Prompt send is monitor-only"
       (or state 'unknown) (or origin 'unknown))))))

(defun ade-prompt--send-normal ()
  "Send or steer the current Prompt to its selected Agent's main thread."
  (let ((agent (ade-prompt--assert-send-context)))
    (when agent (ade-prompt--send-main agent))))

(defun ade-prompt--send-steer ()
  "Steer the selected Agent's active main turn with the Prompt text."
  (let ((agent (ade-prompt--assert-send-context)))
    (when agent
      (if (not (fboundp 'ade-send-steer))
          (ade-prompt--warn "steer protocol is unavailable; send blocked")
        (condition-case err
            (progn
              (ade-prompt--call-steer
               agent (ade-prompt--text)
               (and (fboundp 'ade-agent-current-turn-id)
                    (ade-agent-current-turn-id agent))
               (ade-prompt--callback-in-buffer
                (current-buffer) #'ade-prompt--clear-on-accepted-steer)
               (ade-prompt--callback-in-buffer
                (current-buffer) #'ade-prompt--steer-error))
              t)
          (error
             (ade-prompt--warn "steer failed; Prompt retained: %s"
                               (error-message-string err))))))))

(defun ade-prompt--workspace-agent-candidates (workspace)
  "Return registered Agent records for WORKSPACE in member order."
  (delq nil
        (mapcar #'ade-core-agent-by-id
                (ade-workspace-agent-ids workspace))))

(defun ade-prompt--consult-agent (candidates)
  "Choose one Agent from CANDIDATES using the injected or consult chooser.

Displayed candidates carry the record as a text property, so the selected
payload is never reconstructed by parsing a human-facing string."
  (cond
   ((null candidates) nil)
   (ade-prompt-agent-consult-function
    (funcall ade-prompt-agent-consult-function candidates))
   ((require 'consult nil t)
    (let* ((displayed
            (mapcar
             (lambda (agent)
               (propertize
                (format "%s  state:%s"
                        (ade-agent-id agent)
                        (or (ade-agent-state agent) 'unknown))
                'ade-prompt-agent agent))
             candidates))
           (choice (consult--read displayed
                                   :prompt "ADE Agent: "
                                   :require-match t
                                   :sort nil)))
      (and choice (get-text-property 0 'ade-prompt-agent choice))))
   (t
    (ade-prompt--warn "consult is unavailable; Agent selection blocked"))))

(defun ade-prompt--send-consulted ()
  "Consult for a current-Workspace Agent, select it, then send or steer.

Cancelling with `C-g' leaves the selected Agent, Prompt text, and protocol
state unchanged."
  (unless (ade-prompt-buffer-p)
    (user-error "This buffer is not an ADE Prompt"))
  (let ((workspace (ade-prompt-owner-workspace)))
    (cond
     ((not (ade-prompt-current-workspace-p))
      (ade-prompt--warn
       "Prompt belongs to another current Workspace; Agent consult blocked"))
     ((null workspace)
      (ade-prompt--warn
       "owning Workspace no longer exists; Agent consult blocked"))
     (t
      (let ((agent
             (condition-case nil
                 (ade-prompt--consult-agent
                  (ade-prompt--workspace-agent-candidates workspace))
               (quit nil))))
        (when (and agent
                   (ade-agent-p agent)
                   (member (ade-agent-id agent)
                           (ade-workspace-agent-ids workspace)))
          (ade-core-select-agent (ade-workspace-uuid workspace)
                                 (ade-agent-id agent))
          (ade-prompt--send-main agent)))))))

(defun ade-prompt--side-error (side error)
  "Report side send ERROR for SIDE without clearing Prompt text.

The actual Prompt buffer is captured by `ade-prompt--callback-in-buffer'; SIDE
is accepted here only to match the side adapter's callback signature."
  (ignore side)
  (ade-prompt--warn "side send failed; Prompt retained: %s"
                    (error-message-string error)))

(defun ade-prompt--send-side ()
  "Send the current Prompt to the selected Agent's verified side thread.

Unknown or unverified TUI sides are a no-send boundary.  Only the known side
adapter is called; the command never guesses a thread from terminal output."
  (interactive "P")
  (let ((prefix current-prefix-arg))
    (if prefix
        (ade-prompt--warn "numeric or repeated prefix is no-send")
      (let ((agent (ade-prompt--assert-send-context)))
        (when agent
          (if (not (and (fboundp 'ade-side-known-p)
                        (ade-side-known-p agent)))
              (ade-prompt--warn
               "selected Agent side is unknown; side send blocked")
            (if (not (fboundp 'ade-side-send))
                (ade-prompt--warn "side protocol is unavailable; send blocked")
              (condition-case err
                  (progn
                    (ade-side-send
                     agent (ade-prompt--text)
                     (ade-prompt--callback-in-buffer
                      (current-buffer)
                      (lambda (_side _result)
                        (let ((inhibit-read-only t))
                          (erase-buffer))
                        (ade-prompt--clear-warning)
                        t))
                     (ade-prompt--callback-in-buffer
                      (current-buffer) #'ade-prompt--side-error))
                    t)
                (error
                 (ade-prompt--warn "side send failed; Prompt retained: %s"
                                   (error-message-string err)))))))))))

(defun ade-prompt-send-side (&optional prefix)
  "Send the current Prompt to its selected, verified side thread.

This is the public command bound to `C-c \"'.  `ade-prompt-interrupt' remains
available as a separate explicit command and is never implemented by raw TUI
control-character injection."
  (interactive "P")
  (let ((current-prefix-arg prefix))
    (ade-prompt--send-side)))

(defun ade-prompt-send (&optional prefix)
  "Send the current Prompt, optionally consulting for an Agent.

No prefix uses state-driven main-thread send/steer.  Exactly one raw universal
prefix (`C-u') consults for an Agent, updates Workspace selection, and then
uses the same state-driven dispatch.  Numeric and repeated prefixes are
deliberately rejected and never send anything."
  (interactive "P")
  (cond
   ((null prefix) (ade-prompt--send-normal))
   ((equal prefix '(4)) (ade-prompt--send-consulted))
   (t (ade-prompt--warn
       "numeric or repeated prefix is no-send; use C-u only for Agent consult"))))

(defun ade-prompt-interrupt (&optional prefix)
  "Interrupt the selected Agent's ADE-origin main turn.

Any numeric or repeated prefix is a no-send warning.  The command never sends
raw control characters to a terminal buffer."
  (interactive "P")
  (if prefix
      (ade-prompt--warn "numeric or repeated prefix is no-send")
    (let ((agent (ade-prompt--assert-send-context)))
      (when agent
        (if (not (fboundp 'ade-send-interrupt))
            (ade-prompt--warn "interrupt protocol is unavailable")
          (condition-case err
              (progn
                (ade-send-interrupt agent)
                t)
            (error
             (ade-prompt--warn "interrupt failed: %s"
                               (error-message-string err)))))))))

(defun ade-prompt-enable-skk (&optional hiragana)
  "Explicitly enable WSL Prompt SKK through the platform adapter.

No Prompt hook calls this function automatically.  HIRAGANA requests the
platform helper's optional direct Hiragana start."
  (interactive "P")
  (unless (fboundp 'ade-platform-enable-prompt-skk)
    (user-error "ADE platform SKK helper is unavailable"))
  (ade-platform-enable-prompt-skk hiragana))

(provide 'ade-prompt)

;;; ade-prompt.el ends here
