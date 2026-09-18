;;; ade-perspective.el --- Narrow Perspective.el adapter for ADE -*- lexical-binding: t; -*-

;;; Commentary:

;; ADE commands must not call Perspective.el directly.  This file is the
;; intentionally small adapter boundary.  Keeping the package calls here also
;; makes the registry and Workspace transaction code testable without having
;; Perspective.el installed in a batch test process.

;;; Code:

(require 'ade-core)

(defgroup ade-perspective nil
  "Perspective.el integration for ADE."
  :group 'ade)

(defun ade-perspective--ensure-api ()
  "Load Perspective.el when needed and verify the small API ADE uses."
  (unless (and (fboundp 'persp-current-name)
               (fboundp 'persp-switch)
               (fboundp 'persp-rename)
               (fboundp 'persp-kill))
    (unless (require 'perspective nil t)
      (signal 'ade-unsupported-error
              (list "Perspective.el is not available"))))
  (unless (and (fboundp 'persp-current-name)
               (fboundp 'persp-switch)
               (fboundp 'persp-rename)
               (fboundp 'persp-kill))
    (signal 'ade-unsupported-error
            (list "Perspective.el does not expose the required API")))
  t)

(defun ade-perspective-enabled-p ()
  "Return non-nil when Perspective mode is active."
  (and (boundp 'persp-mode) (symbol-value 'persp-mode)))

(defun ade-perspective-ensure-enabled ()
  "Enable Perspective mode if needed and return non-nil on success."
  (ade-perspective--ensure-api)
  (unless (ade-perspective-enabled-p)
    (if (fboundp 'persp-mode)
        (persp-mode 1)
      (signal 'ade-unsupported-error
              (list "Perspective mode command is not available"))))
  (unless (ade-perspective-enabled-p)
    (signal 'ade-unsupported-error
            (list "Perspective mode did not become active")))
  t)

(defun ade-perspective-current-uuid ()
  "Return the current underlying Perspective name.

The returned value is called a UUID by ADE because all ADE-created
Perspectives use UUID-like immutable names."
  (ade-perspective--ensure-api)
  (let ((name (persp-current-name)))
    (unless (and (stringp name) (not (string-empty-p name)))
      (signal 'ade-invariant-error
              (list "Perspective returned an invalid current name" name)))
    name))

(defun ade-perspective-name-exists-p (name)
  "Return non-nil when Perspective already contains NAME.

When an older Perspective.el does not expose `persp-names', this function
returns nil; the generated UUID collision check remains owned by the ADE
registry."
  (ade-perspective--ensure-api)
  (and (fboundp 'persp-names)
       (member name (persp-names))))

(defun ade-perspective-switch (uuid)
  "Switch to the Perspective whose underlying name is UUID."
  (ade-perspective--ensure-api)
  (unless (and (stringp uuid) (not (string-empty-p uuid)))
    (signal 'ade-invariant-error (list "Invalid Perspective UUID" uuid)))
  (persp-switch uuid)
  uuid)

(defun ade-perspective-create (uuid)
  "Create and select a new Perspective named UUID.

ADE callers pass a freshly generated UUID.  Existing names are rejected when
the installed Perspective.el provides `persp-names'; the registry separately
guards all ADE-known UUIDs."
  (ade-perspective--ensure-api)
  (unless (and (stringp uuid) (not (string-empty-p uuid)))
    (signal 'ade-invariant-error (list "Invalid Perspective UUID" uuid)))
  (when (ade-perspective-name-exists-p uuid)
    (signal 'ade-name-conflict-error (list "Perspective UUID" uuid)))
  ;; `persp-switch' creates a Perspective when the name is absent.  Keeping
  ;; this call in the adapter avoids a catch-all created hook and its
  ;; re-entrancy hazards.
  (persp-switch uuid)
  (unless (equal uuid (persp-current-name))
    (signal 'ade-invariant-error
            (list "Perspective did not select the requested UUID" uuid)))
  uuid)

(defun ade-perspective-rename-current (new-uuid)
  "Rename the current underlying Perspective to NEW-UUID.

This is used only for initial adoption.  Human-facing Workspace renames are
registry operations and must never call this function."
  (ade-perspective--ensure-api)
  (unless (and (stringp new-uuid) (not (string-empty-p new-uuid)))
    (signal 'ade-invariant-error (list "Invalid Perspective UUID" new-uuid)))
  (when (ade-perspective-name-exists-p new-uuid)
    (signal 'ade-name-conflict-error (list "Perspective UUID" new-uuid)))
  (persp-rename new-uuid)
  (unless (equal new-uuid (persp-current-name))
    (signal 'ade-invariant-error
            (list "Perspective rename did not produce requested UUID"
                  new-uuid)))
  new-uuid)

(defun ade-perspective-kill (uuid)
  "Destroy the Perspective identified by UUID.

Perspective.el's optional name argument is used so an inactive Workspace can
be killed without switching the current Perspective.  Buffer cleanup and any
process behaviour remain Perspective/Emacs responsibilities."
  (ade-perspective--ensure-api)
  (unless (and (stringp uuid) (not (string-empty-p uuid)))
    (signal 'ade-invariant-error (list "Invalid Perspective UUID" uuid)))
  ;; Keep the optional-name call in one place.  If a future Perspective.el
  ;; changes this API, only this adapter needs to change.
  (persp-kill uuid)
  t)

(defun ade-perspective-adopt-current (&optional uuid human-name)
  "Adopt the current raw Perspective as an ADE Workspace.

Return a plist containing `:uuid', `:human-name', and `:old-name'.  The same
Perspective object, buffers, windows, and current selection are retained by
calling `persp-rename' exactly once."
  (ade-perspective--ensure-api)
  (let* ((old-name (ade-perspective-current-uuid))
         (new-uuid (or uuid (ade-core-generate-uuid)))
         (name (or human-name old-name)))
    (unless (and (stringp name) (not (string-empty-p name)))
      (signal 'ade-invariant-error (list "Invalid human-facing name" name)))
    (unless (equal old-name new-uuid)
      (ade-perspective-rename-current new-uuid))
    (list :uuid new-uuid :human-name name :old-name old-name)))

(defun ade-perspective-current-p (uuid)
  "Return non-nil when UUID is the current Perspective."
  (equal uuid (ade-perspective-current-uuid)))

(provide 'ade-perspective)

;;; ade-perspective.el ends here
