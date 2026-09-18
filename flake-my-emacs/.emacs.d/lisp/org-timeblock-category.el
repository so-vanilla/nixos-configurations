;;; org-timeblock-category.el --- Category management for org-timeblock -*- lexical-binding: t; -*-

;;; Commentary:
;; Provides category management UI (tabulated-list-mode) and
;; auto-assign / completing-read functions for org-timeblock.

;;; Code:

(require 'org-timeblock-db)

;;; Category list buffer (tabulated-list-mode)

(defvar org-timeblock-category-buffer-name "*Org Timeblock Categories*")

(defun org-timeblock-category--get-entries ()
  "Fetch all categories from DB and return as tabulated-list entries."
  (let* ((categories (org-timeblock-db-get-categories))
         (id-name-map (make-hash-table :test 'equal)))
    ;; Build id -> name map
    (dolist (cat categories)
      (puthash (plist-get cat :id) (plist-get cat :name) id-name-map))
    ;; Build entries
    (mapcar (lambda (cat)
              (let* ((id (plist-get cat :id))
                     (name (plist-get cat :name))
                     (parent-id (plist-get cat :parent-id))
                     (parent-name (if parent-id
                                      (or (gethash parent-id id-name-map) "")
                                    ""))
                     (color (or (plist-get cat :color) ""))
                     (color-display (if (string-empty-p color)
                                        ""
                                      (propertize "████" 'face `(:foreground ,color))))
                     (updated (or (plist-get cat :updated-at) "")))
                (list id (vector (number-to-string id) parent-name name color-display updated))))
            categories)))

(defun org-timeblock-category-refresh ()
  "Refresh the category list buffer."
  (interactive)
  (setq tabulated-list-entries #'org-timeblock-category--get-entries)
  (tabulated-list-revert))

(defun org-timeblock-category--id-at-point ()
  "Return the category ID at point."
  (tabulated-list-get-id))

(defun org-timeblock-category-add (&optional parent-id)
  "Add a new category.  With PARENT-ID, create as child."
  (interactive)
  (let ((name (read-string (if parent-id
                               (format "New child category name (parent ID %d): " parent-id)
                             "New category name: "))))
    (when (string-empty-p name)
      (user-error "Category name cannot be empty"))
    (org-timeblock-db-insert-category name parent-id)
    (org-timeblock-category-refresh)
    (message "Category '%s' added." name)))

(defun org-timeblock-category-add-child ()
  "Add a child category under the category at point."
  (interactive)
  (let ((parent-id (org-timeblock-category--id-at-point)))
    (unless parent-id
      (user-error "No category at point"))
    (org-timeblock-category-add parent-id)))

(defun org-timeblock-category-edit ()
  "Edit the name of the category at point."
  (interactive)
  (let ((id (org-timeblock-category--id-at-point)))
    (unless id
      (user-error "No category at point"))
    (let* ((current-name (aref (tabulated-list-get-entry) 2))
           (new-name (read-string "New name: " current-name)))
      (when (string-empty-p new-name)
        (user-error "Category name cannot be empty"))
      (org-timeblock-db-update-category id new-name)
      (org-timeblock-category-refresh)
      (message "Category renamed to '%s'." new-name))))

(defun org-timeblock-category-delete ()
  "Delete the category at point after confirmation."
  (interactive)
  (let ((id (org-timeblock-category--id-at-point)))
    (unless id
      (user-error "No category at point"))
    (let ((name (aref (tabulated-list-get-entry) 2)))
      (when (y-or-n-p (format "Delete category '%s'? " name))
        (org-timeblock-db-delete-category id)
        (org-timeblock-category-refresh)
        (message "Category '%s' deleted." name)))))

(defvar org-timeblock-category-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'org-timeblock-category-add)
    (define-key map (kbd "c") #'org-timeblock-category-add-child)
    (define-key map (kbd "e") #'org-timeblock-category-edit)
    (define-key map (kbd "d") #'org-timeblock-category-delete)
    (define-key map (kbd "g") #'org-timeblock-category-refresh)
    (define-key map (kbd "q") #'quit-window)
    map))

(define-derived-mode org-timeblock-category-mode tabulated-list-mode "OTB-Category"
  "Major mode for managing org-timeblock categories."
  (setq tabulated-list-format [("ID" 4 t)
                                ("Parent" 15 t)
                                ("Name" 30 t)
                                ("Color" 8 t)
                                ("Updated" 19 t)])
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header))

(defun org-timeblock-category-list ()
  "Display the category management buffer."
  (interactive)
  (let ((buf (get-buffer-create org-timeblock-category-buffer-name)))
    (with-current-buffer buf
      (org-timeblock-category-mode)
      (org-timeblock-category-refresh))
    (pop-to-buffer buf)))

;;; Auto-assign & completing-read

(defun org-timeblock-category-auto-assign (title)
  "Return category-id for TITLE from title-category map, or nil."
  (org-timeblock-db-get-category-for-title title))

(defun org-timeblock-category--completion-candidates ()
  "Return alist of (\"Display Name\" . category-id) for completing-read."
  (let* ((categories (org-timeblock-db-get-categories))
         (id-name-map (make-hash-table :test 'equal)))
    ;; Build id -> name map
    (dolist (cat categories)
      (puthash (plist-get cat :id) (plist-get cat :name) id-name-map))
    (mapcar (lambda (cat)
              (let* ((id (plist-get cat :id))
                     (name (plist-get cat :name))
                     (parent-id (plist-get cat :parent-id))
                     (parent-name (when parent-id (gethash parent-id id-name-map))))
                (cons (if parent-name
                          (format "%s / %s" parent-name name)
                        name)
                      id)))
            categories)))

(defun org-timeblock-category-set-for-worklog (work-log-id title)
  "Prompt user to select a category for WORK-LOG-ID with TITLE."
  (let* ((candidates (org-timeblock-category--completion-candidates))
         (selection (completing-read (format "Category for '%s': " title)
                                     candidates nil t))
         (category-id (cdr (assoc selection candidates))))
    (when category-id
      (org-timeblock-db-update-work-log work-log-id :category-id category-id)
      (org-timeblock-db-upsert-title-category-map title category-id)
      (message "Category set to '%s'." selection))))

(when (require 'hydra nil t)
  (defhydra org-timeblock-category-help (:color blue :hint nil)
    "
 Category ──────────────────────────────────
 _a_ add    _c_ add child  _e_ edit  _d_ delete  _g_ refresh  _q_ quit
"
    ("a" org-timeblock-category-add)
    ("c" org-timeblock-category-add-child)
    ("e" org-timeblock-category-edit)
    ("d" org-timeblock-category-delete)
    ("g" org-timeblock-category-refresh)
    ("q" quit-window))
  (define-key org-timeblock-category-mode-map (kbd "?") #'org-timeblock-category-help/body))

(provide 'org-timeblock-category)
;;; org-timeblock-category.el ends here
