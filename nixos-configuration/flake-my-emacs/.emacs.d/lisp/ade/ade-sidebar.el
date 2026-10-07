;;; ade-sidebar.el --- Global ADE Workspace and Agent sidebar -*- lexical-binding: t; -*-

;;; Commentary:

;; The sidebar is an explicit, global, right-side window.  It is a control
;; plane for switching and selecting only: it never focuses a Ghostel/TUI
;; buffer, edits a Prompt, or opens a request UI while refreshing.  UUIDs stay
;; in text properties and registry lookups, not in user-facing labels.

;;; Code:

(require 'button)
(require 'cl-lib)
(require 'subr-x)
(require 'ade-core)
(require 'ade-state)
(require 'ade-workspace)

(defgroup ade-sidebar nil
  "Global ADE Workspace and Agent sidebar."
  :group 'ade)

(defcustom ade-sidebar-buffer-name "*ADE Sidebar*"
  "Name of the global ADE sidebar buffer."
  :type 'string
  :group 'ade-sidebar)

(defcustom ade-sidebar-window-width 0.28
  "Fractional width requested for the dedicated right sidebar window."
  :type '(choice number integer)
  :group 'ade-sidebar)

(defvar ade-sidebar--buffer nil
  "The global ADE sidebar buffer, created only after explicit opening.")

(defvar ade-sidebar--window nil
  "The current dedicated sidebar window, or nil when hidden.")

(defvar ade-sidebar--refreshing nil
  "Non-nil while the sidebar buffer is being rendered.")

(defun ade-sidebar--ensure-buffer ()
  "Create and initialize the sidebar buffer without displaying it."
  (unless (buffer-live-p ade-sidebar--buffer)
    (setq ade-sidebar--buffer (get-buffer-create ade-sidebar-buffer-name))
    (with-current-buffer ade-sidebar--buffer
      (ade-sidebar-mode)))
  ade-sidebar--buffer)

(defun ade-sidebar--window ()
  "Return the live window displaying the sidebar, or nil."
  (setq ade-sidebar--window
        (or (and (window-live-p ade-sidebar--window)
                 ade-sidebar--window)
            (and (buffer-live-p ade-sidebar--buffer)
                 (get-buffer-window ade-sidebar--buffer t))))
  ade-sidebar--window)

(defun ade-sidebar--workspace-agents (workspace)
  "Return registered Agent records belonging to WORKSPACE in member order."
  (delq nil
        (mapcar #'ade-core-agent-by-id
                (ade-workspace-agent-ids workspace))))

(defun ade-sidebar--request-count (agent)
  "Return pending server request count for AGENT without opening a UI."
  (if (fboundp 'ade-request-pending-for-agent)
      (length (ade-request-pending-for-agent agent))
    (length (ade-agent-pending-requests agent))))

(defun ade-sidebar--short-path (path)
  "Return a user-facing abbreviated PATH or a placeholder."
  (if (and (stringp path) (not (string-empty-p path)))
      (abbreviate-file-name path)
    "-"))

(defun ade-sidebar--workspace-label (workspace agents)
  "Return display text for WORKSPACE and its AGENTS without UUIDs."
  (let* ((current (equal (ade-workspace-uuid workspace)
                         (ade-core-current-uuid)))
         (marker (if current "▸ " "  "))
         (root (ade-sidebar--short-path (ade-workspace-root workspace)))
         (worktree (ade-sidebar--short-path (ade-workspace-worktree workspace)))
         (rollup (ade-state-rollup agents)))
    (format "%s%s  [%s]  agents:%d  state:%s  root:%s  worktree:%s"
            marker (ade-workspace-name workspace) rollup (length agents)
            rollup root worktree)))

(defun ade-sidebar--agent-label (agent)
  "Return display text for AGENT's state and notification metadata."
  (let* ((state (or (ade-agent-state agent) 'unknown))
         (unread (if (ade-agent-unread-p agent) " unread" ""))
         (requests (ade-sidebar--request-count agent))
         (request-label (if (> requests 0)
                            (format " requests:%d" requests)
                          "")))
    (format "    • %s  state:%s%s%s"
            (or (ade-agent-id agent) "unknown") state unread request-label)))

(defun ade-sidebar--insert-workspace (workspace)
  "Insert one Workspace button and its Agent buttons for WORKSPACE."
  (let ((agents (ade-sidebar--workspace-agents workspace))
        (uuid (ade-workspace-uuid workspace)))
    (insert-button
     (concat (ade-sidebar--workspace-label workspace agents) "\n")
     'type 'ade-sidebar-workspace-button
     'ade-sidebar-workspace-uuid uuid
     'follow-link t
     'help-echo "Switch to this ADE Workspace")
    (dolist (agent agents)
      (insert-button
       (concat (ade-sidebar--agent-label agent) "\n")
       'type 'ade-sidebar-agent-button
       'ade-sidebar-workspace-uuid uuid
       'ade-sidebar-agent-id (ade-agent-id agent)
       'follow-link t
       'help-echo "Switch Workspace and select this Agent"))))

(defun ade-sidebar--render ()
  "Render all registry Workspaces and Agents into the current sidebar buffer."
  (let ((inhibit-read-only t)
        (buffer-undo-list t))
    (erase-buffer)
    (insert "ADE Workspaces\n\n")
    (if (null (ade-core-workspaces))
        (insert "  No initialized ADE Workspaces.\n")
      (dolist (workspace (ade-core-workspaces))
        (ade-sidebar--insert-workspace workspace)))))

(defun ade-sidebar-refresh (&optional buffer)
  "Refresh the existing sidebar BUFFER without changing focus or layout.

When the sidebar has not been explicitly opened, this is a no-op.  Incoming
state/request events can therefore refresh an open sidebar without creating a
window or stealing the user's selected window."
  (interactive)
  (let ((buffer (or buffer ade-sidebar--buffer)))
    (when (and (buffer-live-p buffer) (not ade-sidebar--refreshing))
        (let* ((window (get-buffer-window buffer t))
             (point (with-current-buffer buffer (point)))
             (start (and window (window-start window))))
        (let ((ade-sidebar--refreshing t))
          (with-current-buffer buffer
            (ade-sidebar--render)))
        (when (window-live-p window)
          (set-window-point window
                            (min point (with-current-buffer buffer
                                         (point-max))))
          (when (and start (<= start (with-current-buffer buffer
                                       (point-max))))
            (set-window-start window start)))
        ;; `with-current-buffer' and the window point APIs above do not select
        ;; a window.  Deliberately do not call `select-window' here: doing so
        ;; would change the caller's current buffer in batch and can steal the
        ;; user's editing context when an incoming event refreshes the pane.
        ))
    buffer))

(defun ade-sidebar--workspace-action (button)
  "Switch to the Workspace stored on BUTTON and refresh the sidebar."
  (let ((uuid (button-get button 'ade-sidebar-workspace-uuid)))
    (when (and uuid (ade-core-workspace-by-uuid uuid))
      (ade-workspace-switch uuid)
      (ade-sidebar-refresh))))

(defun ade-sidebar--agent-action (button)
  "Switch/select only the Agent stored on BUTTON."
  (let* ((uuid (button-get button 'ade-sidebar-workspace-uuid))
         (agent-id (button-get button 'ade-sidebar-agent-id))
         (agent (and agent-id (ade-core-agent-by-id agent-id))))
    (when (and uuid agent (ade-core-workspace-by-uuid uuid))
      ;; This intentionally performs only Workspace switching and selected
      ;; Agent mutation.  It does not focus Ghostel, display a Prompt, send a
      ;; turn, or answer a pending request.
      (ade-workspace-switch uuid)
      (ade-core-select-agent uuid agent-id)
      (ade-sidebar-refresh))))

(define-button-type 'ade-sidebar-workspace-button
  'action #'ade-sidebar--workspace-action
  'follow-link t)

(define-button-type 'ade-sidebar-agent-button
  'action #'ade-sidebar--agent-action
  'follow-link t)

(defun ade-sidebar-activate ()
  "Activate the ADE sidebar button at point."
  (interactive)
  (let ((button (button-at (point))))
    (if button
        (button-activate button)
      (user-error "No ADE sidebar item at point"))))

(defun ade-sidebar--button-uuid-at (window position)
  "Return Workspace UUID text property at POSITION in WINDOW, or nil."
  (when (and (window-live-p window)
             (integer-or-marker-p position))
    (with-current-buffer (window-buffer window)
      (get-text-property position 'ade-sidebar-workspace-uuid))))

(defun ade-sidebar-drag-workspace (event)
  "Safely reorder a Workspace dragged between Workspace rows.

Only drops whose start and end positions are both Workspace rows are acted
upon.  Drops on headers, Agent rows, other buffers, or invalid positions are
no-ops; no Perspective switch or window focus change is performed."
  (interactive "e")
  (let* ((start (event-start event))
         (end (event-end event))
         (start-window (posn-window start))
         (end-window (posn-window end))
         (start-position (posn-point start))
         (end-position (posn-point end))
         (source (ade-sidebar--button-uuid-at start-window start-position))
         (target (and (eq start-window end-window)
                      (ade-sidebar--button-uuid-at end-window end-position))))
    (when (and (eq start-window (ade-sidebar--window))
               source target
               (not (equal source target)))
      (ade-core-reorder source (ade-core-workspace-index target))
      (ade-sidebar-refresh))))

(defun ade-sidebar-move-workspace (delta)
  "Move the current Workspace by DELTA without switching Perspective."
  (interactive "p")
  (unless (integerp delta)
    (user-error "ADE sidebar move delta must be an integer"))
  (ade-workspace-move delta)
  (ade-sidebar-refresh))

(defun ade-sidebar-move-up ()
  "Move the current Workspace one row up."
  (interactive)
  (ade-sidebar-move-workspace -1))

(defun ade-sidebar-move-down ()
  "Move the current Workspace one row down."
  (interactive)
  (ade-sidebar-move-workspace 1))

(define-derived-mode ade-sidebar-mode special-mode "ADE-Sidebar"
  "Major mode for the global ADE Workspace and Agent sidebar."
  (setq-local truncate-lines t)
  (setq-local buffer-read-only t)
  (use-local-map (copy-keymap (current-local-map)))
  (define-key (current-local-map) (kbd "RET") #'ade-sidebar-activate)
  (define-key (current-local-map) (kbd "g") #'ade-sidebar-refresh)
  (define-key (current-local-map) (kbd "C-c <up>") #'ade-sidebar-move-up)
  (define-key (current-local-map) (kbd "C-c <down>") #'ade-sidebar-move-down)
  (define-key (current-local-map) (kbd "<drag-mouse-1>")
              #'ade-sidebar-drag-workspace))

(defun ade-sidebar-open ()
  "Open the global ADE sidebar in a dedicated right-side window."
  (interactive)
  (let* ((buffer (ade-sidebar--ensure-buffer))
         (window
          (display-buffer-in-side-window
           buffer
           `((side . right)
             (slot . 0)
             (window-width . ,ade-sidebar-window-width)))))
    (setq ade-sidebar--window window)
    (set-window-dedicated-p window t)
    (ade-sidebar-refresh buffer)
    window))

(defun ade-sidebar-close ()
  "Close the ADE sidebar window while retaining its buffer and state."
  (interactive)
  (when-let* ((window (ade-sidebar--window)))
    (delete-window window)
    (setq ade-sidebar--window nil))
  t)

(defun ade-sidebar-toggle ()
  "Toggle the explicit global ADE sidebar without changing its contents."
  (interactive)
  (if (ade-sidebar--window)
      (progn (ade-sidebar-close) nil)
    (ade-sidebar-open)))

(defun ade-sidebar--state-change (_agent _event)
  "Refresh an already-open sidebar after an Agent state/request event."
  (when (ade-sidebar--window)
    (ade-sidebar-refresh)))

(add-hook 'ade-state-change-hook #'ade-sidebar--state-change)

(provide 'ade-sidebar)

;;; ade-sidebar.el ends here
