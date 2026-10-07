;;; ade-workspace.el --- ADE Workspace lifecycle and navigation -*- lexical-binding: t; -*-

;;; Commentary:

;; This is the user-facing Workspace layer.  It owns lifecycle transactions
;; and delegates every underlying Perspective operation to
;; `ade-perspective.el'.  The registry is updated only at the same boundaries
;; as successful adapter calls, so a cancelled or failed operation does not
;; silently lose ADE ownership.

;;; Code:

(require 'cl-lib)
(require 'ade-core)
(require 'ade-perspective)

(defgroup ade-workspace nil
  "ADE Workspace lifecycle and navigation."
  :group 'ade)

(defun ade-workspace--notify (format-string &rest args)
  "Report an ADE Workspace message using FORMAT-STRING and ARGS."
  (apply #'message (concat "ADE: " format-string) args))

(defun ade-workspace--canonical-directory (directory)
  "Return DIRECTORY as an absolute directory name, or signal an error."
  (unless (and (stringp directory) (file-directory-p directory))
    (signal 'ade-invariant-error (list "Workspace root is not a directory"
                                       directory)))
  (file-name-as-directory (file-truename directory)))

(defun ade-workspace-detect-root (&optional buffer)
  "Return the Project root for BUFFER, falling back to `default-directory'.

No Workspace is created and no worktree is made by this function."
  (let ((buffer (or buffer (current-buffer)))
        (root nil))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (fboundp 'project-current)
          (when-let* ((project (project-current nil)))
            (when (fboundp 'project-root)
              (setq root (project-root project)))))))
    (ade-workspace--canonical-directory
     (or root
         (and (buffer-live-p buffer)
              (buffer-local-value 'default-directory buffer))
         default-directory))))

(defun ade-workspace--read-root (root)
  "Return ROOT, asking for confirmation only during an interactive command."
  (let ((detected (or root (ade-workspace-detect-root))))
    (if (called-interactively-p 'interactive)
        (ade-workspace--canonical-directory
         (read-directory-name "ADE Workspace root: " detected detected t))
      (ade-workspace--canonical-directory detected))))

(defun ade-workspace--resolve-id (value)
  "Resolve VALUE as a Workspace UUID or human-facing name."
  (cond
   ((and (stringp value) (ade-core-workspace-by-uuid value)) value)
   ((and (stringp value) (ade-core-workspace-by-name value))
    (ade-workspace-uuid (ade-core-workspace-by-name value)))
   (t
    (signal 'ade-not-found-error (list "Workspace" value)))))

(defun ade-workspace--new-record (uuid name root)
  "Build an Agent-less Workspace record for UUID, NAME, and ROOT."
  (ade-workspace-create :uuid uuid
                        :name name
                        :root root
                        :worktree nil
                        :perspective-name uuid
                        :prompt-buffer nil
                        :agent-ids nil
                        :selected-agent-id nil
                        :metadata nil))

(defun ade-workspace-current ()
  "Return the current ADE Workspace, or nil."
  (ade-core-current-workspace))

(defun ade-workspace-init (&optional root human-name)
  "Initialize the current Perspective as an ADE Workspace.

ROOT is preferred when supplied.  Otherwise the current buffer's Project root
is detected, falling back to `default-directory'.  HUMAN-NAME defaults to the
current Perspective's human-facing name.  Initialization is idempotent: an
already registered Workspace, its Agents, Prompt, and connections are left
untouched.  This function does not launch or scan for Agents."
  (interactive)
  (ade-perspective-ensure-enabled)
  (let* ((current-name (ade-perspective-current-uuid))
         (existing (ade-core-workspace-by-uuid current-name)))
    (if existing
        (progn
          (ade-core-set-current current-name)
          existing)
      (let* ((workspace-root (ade-workspace--read-root root))
             (proposed-name (or human-name current-name)))
        (when (ade-core-workspace-by-name proposed-name)
          (signal 'ade-name-conflict-error
                  (list "Workspace name" proposed-name)))
        (let* ((adoption (ade-perspective-adopt-current))
             (uuid (plist-get adoption :uuid))
             (name (or human-name (plist-get adoption :human-name)))
             (workspace (ade-workspace--new-record uuid name workspace-root)))
          (condition-case err
              (progn
                (ade-core-register-workspace workspace)
                (ade-core-set-current uuid)
                workspace)
            (error
             ;; The Perspective was renamed, but no registry entry is retained
             ;; when registration fails.  There is no supported raw recovery
             ;; path; report the failure for correction rather than inventing an
             ;; automatic adoption UI.
             (ade-workspace--notify "initialization failed: %s"
                                    (error-message-string err))
             (signal (car err) (cdr err)))))))))

(defun ade-workspace-bootstrap-current ()
  "Idempotently initialize only the current Perspective.

This is suitable for `persp-mode-hook'.  It deliberately does not create a
Prompt buffer or show the sidebar; explicit UI commands own those actions."
  (when (ade-perspective-enabled-p)
    (unless (and (ade-perspective-current-uuid)
                 (ade-core-workspace-by-uuid
                  (ade-perspective-current-uuid)))
      (ade-workspace-init))))

(defun ade-workspace-enable-bootstrap ()
  "Install the idempotent bootstrap on `persp-mode-hook'."
  (interactive)
  (add-hook 'persp-mode-hook #'ade-workspace-bootstrap-current)
  (when (ade-perspective-enabled-p)
    (ade-workspace-bootstrap-current))
  t)

(defun ade-workspace-create-or-attach (name &optional root)
  "Attach to existing human-facing NAME or create a new Workspace.

Existing names always switch to that Workspace.  A new Workspace receives a
fresh UUID underlying Perspective name and is Agent-less.  ROOT is used only
when a new Workspace is created."
  (interactive
   (list (completing-read
          "ADE Workspace (existing or new): "
          (mapcar #'ade-workspace-name (ade-core-workspaces))
          nil nil)))
  (unless (and (stringp name) (not (string-empty-p name)))
    (user-error "ADE Workspace name must not be empty"))
  (if-let* ((existing (ade-core-workspace-by-name name)))
      (ade-workspace-switch (ade-workspace-uuid existing))
    (let* ((old-current (ade-core-current-uuid))
           (workspace-root (ade-workspace--read-root root))
           (uuid (ade-core-generate-uuid))
           (workspace (ade-workspace--new-record uuid name workspace-root)))
      (condition-case err
          (progn
            (ade-perspective-create uuid)
            (condition-case register-error
                (progn
                  (ade-core-register-workspace workspace)
                  (ade-core-set-current uuid)
                  workspace)
              (error
               (ignore-errors (ade-perspective-kill uuid))
               (when (and old-current
                          (ade-core-workspace-by-uuid old-current))
                 (ignore-errors (ade-perspective-switch old-current)))
               (signal (car register-error) (cdr register-error)))))
        (error
         (ade-workspace--notify "create failed: %s"
                                (error-message-string err))
         (signal (car err) (cdr err)))))))

(defun ade-workspace-switch (value)
  "Switch to Workspace VALUE, resolved by UUID or human-facing name."
  (interactive
   (list (completing-read "Switch ADE Workspace: "
                         (mapcar #'ade-workspace-name
                                 (ade-core-workspaces))
                         nil t)))
  (let* ((uuid (ade-workspace--resolve-id value))
         (workspace (ade-core-workspace-by-uuid uuid)))
    (ade-perspective-switch uuid)
    (ade-core-set-current uuid)
    workspace))

(defun ade-workspace-rename (new-name &optional value)
  "Rename a Workspace to NEW-NAME without changing its UUID.

VALUE is resolved by UUID or human-facing name and defaults to the current
Workspace.  Existing names are rejected; no old-name alias is retained."
  (interactive
   (list (read-string "New ADE Workspace name: ") nil))
  (let* ((uuid (ade-workspace--resolve-id (or value (ade-core-current-uuid))))
         (workspace (ade-core-rename-workspace uuid new-name)))
    (ade-workspace--notify "renamed Workspace to %s"
                           (ade-workspace-name workspace))
    workspace))

(defun ade-workspace-move (delta)
  "Move the current Workspace by DELTA positions without switching it."
  (interactive "p")
  (ade-core-move-current delta))

(defun ade-workspace-next ()
  "Switch to the next Workspace in ADE order, wrapping at the end."
  (interactive)
  (unless (ade-core-current-uuid)
    (signal 'ade-no-current-workspace-error nil))
  (ade-workspace-switch
   (ade-core-adjacent-uuid (ade-core-current-uuid) 1)))

(defun ade-workspace-prev ()
  "Switch to the previous Workspace in ADE order, wrapping at the start."
  (interactive)
  (unless (ade-core-current-uuid)
    (signal 'ade-no-current-workspace-error nil))
  (ade-workspace-switch
   (ade-core-adjacent-uuid (ade-core-current-uuid) -1)))

(defun ade-workspace-select-number (number)
  "Switch to one-based Workspace NUMBER in explicit ADE order."
  (interactive "nADE Workspace number: ")
  (unless (and (integerp number) (> number 0))
    (user-error "ADE Workspace number must be positive: %s" number))
  (let ((uuid (nth (1- number) (mapcar #'ade-workspace-uuid
                                       (ade-core-workspaces)))))
    (unless uuid
      (user-error "No ADE Workspace numbered %s" number))
    (ade-workspace-switch uuid)))

(defun ade-workspace--replacement-name (old-name)
  "Return the fixed replacement name for the last Workspace OLD-NAME."
  (cond
   ((equal old-name "main") "main2")
   ((equal old-name "main2") "main")
   (t "main")))

(defun ade-workspace--confirm-kill (workspace confirm-function)
  "Confirm killing WORKSPACE once using CONFIRM-FUNCTION when supplied."
  (if confirm-function
      (funcall confirm-function (ade-workspace-name workspace))
    (yes-or-no-p (format "Kill ADE Workspace %s? "
                         (ade-workspace-name workspace)))))

(defun ade-workspace--restore-after-failure (uuid)
  "Best-effort restore of current Workspace UUID after a failed transaction."
  (condition-case err
      (progn
        (ade-workspace-switch uuid)
        t)
    (error
     (ade-workspace--notify "could not restore Workspace %s: %s"
                            uuid (error-message-string err))
     nil)))

(defun ade-workspace--kill-last (workspace)
  "Kill the only WORKSPACE with create-before-kill replacement semantics."
  (let* ((old-uuid (ade-workspace-uuid workspace))
         (replacement-name (ade-workspace--replacement-name
                            (ade-workspace-name workspace)))
         (replacement-uuid (ade-core-generate-uuid))
         (replacement (ade-workspace--new-record
                       replacement-uuid replacement-name
                       (ade-workspace-root workspace))))
    ;; Create and select the replacement before touching OLD-UUID.  This
    ;; prevents Perspective.el from manufacturing a raw `main' fallback.
    (condition-case create-error
        (progn
          (ade-perspective-create replacement-uuid)
          (condition-case register-error
              (progn
                (ade-core-register-workspace replacement)
                (ade-core-set-current replacement-uuid))
            (error
             (ignore-errors (ade-perspective-kill replacement-uuid))
             (ignore-errors (ade-perspective-switch old-uuid))
             (signal (car register-error) (cdr register-error)))))
      (error
       (ade-workspace--notify "replacement creation failed: %s"
                              (error-message-string create-error))
       (signal (car create-error) (cdr create-error))))
    (condition-case kill-error
        (progn
          (ade-perspective-kill old-uuid)
          (ade-core-unregister-workspace old-uuid)
          (ade-core-set-current replacement-uuid)
          replacement)
      (error
       ;; The old Workspace remains registered.  Attempt one cleanup of the
       ;; newly created replacement; no retry or extra confirmation is added.
       (let ((cleanup-ok
              (condition-case cleanup-error
                  (progn
                    (ade-perspective-kill replacement-uuid)
                    (unless (ade-workspace--restore-after-failure old-uuid)
                      (error "Could not restore old Workspace %s" old-uuid))
                    (ade-core-unregister-workspace replacement-uuid)
                    t)
                (error
                 (ade-workspace--notify
                  "replacement cleanup failed: %s"
                  (error-message-string cleanup-error))
                 nil))))
         (unless cleanup-ok
           ;; Both registry records intentionally remain so the user can
           ;; continue with ordinary create/kill operations and the defect is
           ;; observable.  Do not perform automatic destructive recovery.
           (ade-workspace--notify
            "Workspace kill failed; old and replacement Workspaces remain"))
         (ade-workspace--notify "Workspace kill failed: %s"
                                (error-message-string kill-error))
         (signal (car kill-error) (cdr kill-error)))))))

(defun ade-workspace-kill (&optional value confirm-function)
  "Kill Workspace VALUE after one human-facing-name confirmation.

VALUE may be a UUID or human-facing name and defaults to the current
Workspace.  CONFIRM-FUNCTION is a test hook receiving the human-facing name.
The registry is modified only after `ade-perspective-kill' returns normally.
The last Workspace is replaced by a fresh Agent-less `main' or `main2'
Workspace before the old Perspective is destroyed."
  (interactive
   (list (completing-read "Kill ADE Workspace: "
                         (mapcar #'ade-workspace-name
                                 (ade-core-workspaces))
                         nil t)
         nil))
  (let* ((uuid (ade-workspace--resolve-id
                (or value (ade-core-current-uuid))))
         (workspace (ade-core-workspace-by-uuid uuid)))
    (if (not (ade-workspace--confirm-kill workspace confirm-function))
        (progn
          (ade-workspace--notify "kill cancelled for %s"
                                 (ade-workspace-name workspace))
          nil)
      (if (= 1 (ade-core-workspace-count))
          (ade-workspace--kill-last workspace)
        (let* ((active-p (equal uuid (ade-core-current-uuid)))
               (next-uuid (and active-p
                               (ade-core-adjacent-uuid uuid 1))))
          (when active-p
            (ade-workspace-switch next-uuid))
          (condition-case kill-error
              (progn
                (ade-perspective-kill uuid)
                (ade-core-unregister-workspace uuid)
                (ade-workspace--notify "killed Workspace %s"
                                       (ade-workspace-name workspace))
                t)
            (error
             (when active-p
               (ade-workspace--restore-after-failure uuid))
             (ade-workspace--notify "Workspace kill failed: %s"
                                    (error-message-string kill-error))
             (signal (car kill-error) (cdr kill-error)))))))))

(provide 'ade-workspace)

;;; ade-workspace.el ends here
