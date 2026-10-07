;;; org-timeblock-worklog.el --- Work log management for org-timeblock -*- lexical-binding: t; -*-

;;; Commentary:
;; Provides work log operations: confirm/modify/cancel, clock-in/out,
;; insert, boundary adjustment, break management, date navigation,
;; category summary, past-date viewing, alerts, cleanup, and org-journal export.

;;; Code:

(require 'org-timeblock-db)

;; Forward declarations for display.el functions
(declare-function org-timeblock-display--entry-at-point "org-timeblock-display" ())
(declare-function org-timeblock-display--render "org-timeblock-display" (date))
(declare-function org-timeblock-display-refresh "org-timeblock-display" (&optional date))
(declare-function org-timeblock-display--minutes-to-time-string "org-timeblock-display" (minutes))
(declare-function org-timeblock-display--time-string-to-minutes "org-timeblock-display" (time-str))
(declare-function org-timeblock-display--row-to-minutes "org-timeblock-display" (row))
(declare-function org-timeblock-display-show "org-timeblock-display" (&optional date))

;; Forward declarations for category.el functions
(declare-function org-timeblock-category-auto-assign "org-timeblock-category" (title))
(declare-function org-timeblock-category-set-for-worklog "org-timeblock-category" (work-log-id title))
(declare-function org-timeblock-category-list "org-timeblock-category" ())
(declare-function org-timeblock-db-get-known-titles "org-timeblock-db" ())

;; External variables from display.el
(defvar org-timeblock-display--current-date)
(defvar org-timeblock-display--line-map)
(defvar org-timeblock-display-mode-map)
(defvar org-timeblock-display-start-hour)
(defvar org-timeblock-display-end-hour)

;;; ---- Customization ----

(defcustom org-timeblock-worklog-other-category "Other"
  "Category name for unaccounted time in work hour summary.
Gaps between confirmed entries within the clock-in/clock-out window
are attributed to this category.
Specify a category name like \"Other\" or \"Parent / Child\" for a subcategory."
  :type 'string
  :group 'org-timeblock-display)

(defcustom org-timeblock-worklog-break-start "12:00"
  "Default break start time (HH:MM)."
  :type 'string
  :group 'org-timeblock-display)

(defcustom org-timeblock-worklog-break-end "13:00"
  "Default break end time (HH:MM)."
  :type 'string
  :group 'org-timeblock-display)

(defcustom org-timeblock-worklog-break-title "Break"
  "Display title for break entries in the sidebar."
  :type 'string
  :group 'org-timeblock-display)

;;; ---- Time helpers ----

(defun org-timeblock-worklog--time-to-minutes (time-str)
  "Convert TIME-STR (HH:MM) to minutes from midnight."
  (when (and time-str (string-match "\\`\\([0-9]+\\):\\([0-9]+\\)\\'" time-str))
    (+ (* (string-to-number (match-string 1 time-str)) 60)
       (string-to-number (match-string 2 time-str)))))

(defun org-timeblock-worklog--minutes-to-time (minutes)
  "Convert MINUTES from midnight to HH:MM string."
  (format "%02d:%02d" (/ minutes 60) (mod minutes 60)))

(defun org-timeblock-worklog--time-add (time-str delta)
  "Add DELTA minutes to TIME-STR (HH:MM). Return new HH:MM string."
  (org-timeblock-worklog--minutes-to-time
   (+ (org-timeblock-worklog--time-to-minutes time-str) delta)))

(defun org-timeblock-worklog--current-time-minutes ()
  "Return current time as minutes from midnight."
  (let ((now (decode-time)))
    (+ (* (nth 2 now) 60) (nth 1 now))))

(defun org-timeblock-worklog--round-to-15 (minutes)
  "Round MINUTES to the nearest 15-minute boundary."
  (let ((remainder (mod minutes 15)))
    (if (>= remainder 8)
        (+ minutes (- 15 remainder))
      (- minutes remainder))))

(defun org-timeblock-worklog--cursor-minutes ()
  "Return the start minutes of the 15-min slot at cursor position."
  (org-timeblock-display--row-to-minutes (1- (line-number-at-pos))))

;;; ---- Title completion ----

(defun org-timeblock-worklog--title-completion-table ()
  "Return a completion table of known titles with category annotations.
Past category mappings are shown via annotation-function (marginalia).
Displays \"Parent / Child\" format for child categories."
  (let* ((titles (org-timeblock-db-get-known-titles))
         (title-ann-map (make-hash-table :test 'equal))
         (categories (when (fboundp 'org-timeblock-db-get-categories)
                       (org-timeblock-db-get-categories)))
         (cat-name-map (make-hash-table :test 'equal)))
    (dolist (cat categories)
      (puthash (plist-get cat :id) cat cat-name-map))
    (dolist (title titles)
      (when-let* ((cat-id (org-timeblock-db-get-category-for-title title))
                  (cat (gethash cat-id cat-name-map)))
        (let* ((name (plist-get cat :name))
               (parent-id (plist-get cat :parent-id))
               (parent (when parent-id (gethash parent-id cat-name-map)))
               (display (if parent
                            (format "%s / %s" (plist-get parent :name) name)
                          name)))
          (puthash title display title-ann-map))))
    (lambda (string pred action)
      (if (eq action 'metadata)
          `(metadata
            (annotation-function
             . ,(lambda (title)
                  (when-let ((display (gethash title title-ann-map)))
                    (propertize (format "  %s" display) 'face 'shadow)))))
        (complete-with-action action titles string pred)))))

;;; ---- Date helpers ----

(defun org-timeblock-worklog--current-date-string ()
  "Return the current display date as \"YYYY-MM-DD\" string."
  (when org-timeblock-display--current-date
    (let ((month (nth 0 org-timeblock-display--current-date))
          (day (nth 1 org-timeblock-display--current-date))
          (year (nth 2 org-timeblock-display--current-date)))
      (format "%04d-%02d-%02d" year month day))))

(defun org-timeblock-worklog--date-string-to-display-date (date-str)
  "Convert DATE-STR (YYYY-MM-DD) to display date (MONTH DAY YEAR)."
  (when (string-match "\\`\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)\\'" date-str)
    (list (string-to-number (match-string 2 date-str))
          (string-to-number (match-string 3 date-str))
          (string-to-number (match-string 1 date-str)))))

(defun org-timeblock-worklog--refresh ()
  "Refresh the display buffer for the current date."
  (when org-timeblock-display--current-date
    (org-timeblock-display--render org-timeblock-display--current-date)))

;;; ---- Entry -> DB log matching ----

(defun org-timeblock-worklog--find-db-log-for-entry (entry)
  "Find the DB work log matching display ENTRY.
Returns the DB log plist or nil."
  (when (and entry
             (plist-get entry :confirmed-p)
             (eq (plist-get entry :source) 'db))
    (let* ((date-str (org-timeblock-worklog--current-date-string))
           (logs (org-timeblock-db-get-work-logs-by-date date-str))
           (title (plist-get entry :title))
           (start-str (org-timeblock-worklog--minutes-to-time
                       (plist-get entry :start-minutes))))
      (seq-find (lambda (l)
                  (and (equal (plist-get l :title) title)
                       (equal (plist-get l :start-time) start-str)))
                logs))))

;;; ---- Range utilities ----

(defun org-timeblock-worklog--subtract-ranges (start end blocked-ranges)
  "Return non-overlapping segments from START to END after removing BLOCKED-RANGES.
BLOCKED-RANGES is a list of (start . end) cons cells (minutes).
Returns a list of (start . end) cons cells."
  (let ((sorted (sort (copy-sequence blocked-ranges)
                      (lambda (a b) (< (car a) (car b)))))
        (segments nil)
        (cursor start))
    (dolist (range sorted)
      (let ((rs (car range))
            (re (cdr range)))
        (when (> (min rs end) cursor)
          (push (cons cursor (min rs end)) segments))
        (setq cursor (max cursor re))))
    (when (< cursor end)
      (push (cons cursor end) segments))
    (nreverse segments)))

;;; ---- Confirm / Modify / Cancel ----

(defun org-timeblock-worklog--confirm-segments (entry cat-id)
  "Insert ENTRY as work log segments, skipping already-confirmed time ranges.
Returns the number of segments inserted."
  (let* ((date-str (org-timeblock-worklog--current-date-string))
         (title (plist-get entry :title))
         (start-min (plist-get entry :start-minutes))
         (end-min (plist-get entry :end-minutes))
         (all-logs (org-timeblock-db-get-work-logs-by-date date-str))
         (blocked (mapcar (lambda (log)
                            (cons (org-timeblock-worklog--time-to-minutes (plist-get log :start-time))
                                  (org-timeblock-worklog--time-to-minutes (plist-get log :end-time))))
                          all-logs))
         (segments (org-timeblock-worklog--subtract-ranges start-min end-min blocked)))
    (dolist (seg segments)
      (org-timeblock-db-insert-work-log
       date-str title
       (org-timeblock-worklog--minutes-to-time (car seg))
       (org-timeblock-worklog--minutes-to-time (cdr seg))
       cat-id "org"))
    (length segments)))

(defun org-timeblock-worklog-confirm ()
  "Confirm the event at point as work log entries.
Only fills non-overlapping time segments (existing confirmed entries are preserved).
Auto-assigns category from title_category_map."
  (interactive)
  (let ((entry (org-timeblock-display--entry-at-point)))
    (unless entry
      (user-error "No entry at point"))
    (when (plist-get entry :confirmed-p)
      (user-error "Entry already confirmed"))
    (let* ((title (plist-get entry :title))
           (cat-id (org-timeblock-category-auto-assign title))
           (n (org-timeblock-worklog--confirm-segments entry cat-id)))
      (when (and cat-id (> n 0))
        (org-timeblock-db-upsert-title-category-map title cat-id))
      (if (> n 0)
          (message "Confirmed: %s (%d segment%s)" title n (if (> n 1) "s" ""))
        (message "Fully covered by existing entries, nothing to confirm")))
    (org-timeblock-worklog--refresh)))

(defun org-timeblock-worklog-confirm-with-category ()
  "Confirm the event at point with category selection.
Only fills non-overlapping time segments."
  (interactive)
  (let ((entry (org-timeblock-display--entry-at-point)))
    (unless entry
      (user-error "No entry at point"))
    (when (plist-get entry :confirmed-p)
      (user-error "Entry already confirmed"))
    (let* ((n (org-timeblock-worklog--confirm-segments entry nil)))
      (when (> n 0)
        ;; Set category for the first inserted segment
        (let* ((date-str (org-timeblock-worklog--current-date-string))
               (logs (org-timeblock-db-get-work-logs-by-date date-str))
               (title (plist-get entry :title))
               (matching (seq-filter (lambda (l)
                                       (equal (plist-get l :title) title))
                                     logs)))
          (dolist (log matching)
            (org-timeblock-category-set-for-worklog (plist-get log :id) title))))
      (if (> n 0)
          (message "Confirmed with category: %s (%d segment%s)"
                   (plist-get entry :title) n (if (> n 1) "s" ""))
        (message "Fully covered, nothing to confirm")))
    (org-timeblock-worklog--refresh)))

(defun org-timeblock-worklog--move-entry (delta)
  "Move confirmed entry at point by DELTA minutes."
  (let* ((entry (org-timeblock-display--entry-at-point))
         (log (org-timeblock-worklog--find-db-log-for-entry entry)))
    (unless log
      (user-error "No confirmed DB entry at point"))
    (let* ((date-str (org-timeblock-worklog--current-date-string))
           (id (plist-get log :id))
           (new-start (org-timeblock-worklog--time-add (plist-get log :start-time) delta))
           (new-end (org-timeblock-worklog--time-add (plist-get log :end-time) delta)))
      (when (org-timeblock-db-check-collision date-str new-start new-end id)
        (user-error "Time collision detected"))
      (org-timeblock-db-update-work-log id :start-time new-start :end-time new-end)
      (message "Moved to %s-%s" new-start new-end))
    (org-timeblock-worklog--refresh)))

(defun org-timeblock-worklog-move-up ()
  "Move confirmed entry at point 15 minutes up."
  (interactive)
  (org-timeblock-worklog--move-entry -15))

(defun org-timeblock-worklog-move-down ()
  "Move confirmed entry at point 15 minutes down."
  (interactive)
  (org-timeblock-worklog--move-entry 15))

(defun org-timeblock-worklog-cancel ()
  "Cancel (delete) the confirmed entry at point."
  (interactive)
  (let* ((entry (org-timeblock-display--entry-at-point))
         (log (org-timeblock-worklog--find-db-log-for-entry entry)))
    (unless log
      (user-error "No confirmed DB entry at point"))
    (when (y-or-n-p (format "Cancel \"%s\" (%s-%s)? "
                            (plist-get log :title)
                            (plist-get log :start-time)
                            (plist-get log :end-time)))
      (org-timeblock-db-delete-work-log (plist-get log :id))
      (message "Cancelled: %s" (plist-get log :title))
      (org-timeblock-worklog--refresh))))

;;; ---- Category reassignment ----

(defun org-timeblock-worklog-set-category ()
  "Set or change category for the confirmed entry at point."
  (interactive)
  (let* ((entry (org-timeblock-display--entry-at-point))
         (log (org-timeblock-worklog--find-db-log-for-entry entry)))
    (unless log
      (user-error "No confirmed DB entry at point"))
    (org-timeblock-category-set-for-worklog (plist-get log :id) (plist-get log :title))
    (org-timeblock-worklog--refresh)))

;;; ---- Clock-in / Clock-out (global commands) ----

(defun org-timeblock-worklog-clock-in ()
  "Record clock-in time via minibuffer prompt.
Default is current time HH:MM."
  (interactive)
  (let* ((date-str (format-time-string "%Y-%m-%d"))
         (default (format-time-string "%H:%M"))
         (time-str (read-string "Clock-in: " default)))
    (org-timeblock-db-clock-in date-str time-str)
    (message "Clocked in at %s on %s" time-str date-str)
    (org-timeblock-display-refresh)))

(defun org-timeblock-worklog-clock-out ()
  "Record clock-out time via minibuffer prompt.
Default is current time HH:MM."
  (interactive)
  (let* ((date-str (format-time-string "%Y-%m-%d"))
         (default (format-time-string "%H:%M"))
         (time-str (read-string "Clock-out: " default)))
    (org-timeblock-db-clock-out date-str time-str)
    (message "Clocked out at %s on %s" time-str date-str)
    (org-timeblock-display-refresh)))

(defun org-timeblock-worklog-clock-in-date ()
  "Record clock-in for a specified date and time.
Prompts for date via `org-read-date', then for time (default now)."
  (interactive)
  (let* ((date-str (org-read-date nil nil nil "Clock-in date: "))
         (default (format-time-string "%H:%M"))
         (time-str (read-string (format "Clock-in time (%s): " date-str) default)))
    (org-timeblock-db-clock-in date-str time-str)
    (message "Clocked in at %s on %s" time-str date-str)
    (org-timeblock-display-refresh)))

(defun org-timeblock-worklog-clock-out-date ()
  "Record clock-out for a specified date and time.
Prompts for date via `org-read-date', then for time (default now)."
  (interactive)
  (let* ((date-str (org-read-date nil nil nil "Clock-out date: "))
         (default (format-time-string "%H:%M"))
         (time-str (read-string (format "Clock-out time (%s): " date-str) default)))
    (org-timeblock-db-clock-out date-str time-str)
    (message "Clocked out at %s on %s" time-str date-str)
    (org-timeblock-display-refresh)))

;;; ---- Insert (cursor / region) ----

(defun org-timeblock-worklog-insert ()
  "Insert a work log at cursor position or over the active region.
Without region: inserts a 15-min entry at the cursor's time slot.
With region: inserts an entry spanning the selected rows.
If overlapping existing entries, prompts y/n then shrinks or deletes them."
  (interactive)
  (let* ((start-minutes
          (if (use-region-p)
              (save-excursion
                (goto-char (region-beginning))
                (org-timeblock-display--row-to-minutes (1- (line-number-at-pos))))
            (org-timeblock-worklog--cursor-minutes)))
         (end-minutes
          (if (use-region-p)
              (save-excursion
                (goto-char (region-end))
                (when (and (bolp) (> (point) (region-beginning)))
                  (forward-line -1))
                (+ (org-timeblock-display--row-to-minutes (1- (line-number-at-pos))) 15))
            (+ (org-timeblock-worklog--cursor-minutes) 15)))
         (date-str (org-timeblock-worklog--current-date-string))
         (start-str (org-timeblock-worklog--minutes-to-time start-minutes))
         (end-str (org-timeblock-worklog--minutes-to-time end-minutes))
         (title (completing-read (format "Title (%s-%s): " start-str end-str)
                                 (org-timeblock-worklog--title-completion-table) nil nil))
         (all-logs (org-timeblock-db-get-work-logs-by-date date-str))
         (collisions (seq-filter
                      (lambda (log)
                        (let ((ls (org-timeblock-worklog--time-to-minutes (plist-get log :start-time)))
                              (le (org-timeblock-worklog--time-to-minutes (plist-get log :end-time))))
                          (and (< ls end-minutes) (> le start-minutes))))
                      all-logs)))
    (when (string-empty-p title)
      (user-error "Title cannot be empty"))
    ;; Handle collisions
    (when collisions
      (let ((desc (mapconcat
                   (lambda (l)
                     (format "%s (%s-%s)"
                             (plist-get l :title)
                             (plist-get l :start-time)
                             (plist-get l :end-time)))
                   collisions ", ")))
        (unless (y-or-n-p (format "Overlaps: %s. Overwrite? " desc))
          (user-error "Cancelled"))))
    ;; Process collisions: shrink or delete affected entries
    (dolist (log collisions)
      (let ((ls (org-timeblock-worklog--time-to-minutes (plist-get log :start-time)))
            (le (org-timeblock-worklog--time-to-minutes (plist-get log :end-time)))
            (lid (plist-get log :id)))
        (cond
         ;; Fully covered: delete
         ((and (>= ls start-minutes) (<= le end-minutes))
          (org-timeblock-db-delete-work-log lid))
         ;; Overlap at end of existing: shrink end
         ((and (< ls start-minutes) (> le start-minutes) (<= le end-minutes))
          (org-timeblock-db-update-work-log lid :end-time start-str))
         ;; Overlap at start of existing: shrink start
         ((and (>= ls start-minutes) (< ls end-minutes) (> le end-minutes))
          (org-timeblock-db-update-work-log lid :start-time end-str))
         ;; New entry contained within existing: split
         ((and (< ls start-minutes) (> le end-minutes))
          (org-timeblock-db-update-work-log lid :end-time start-str)
          (org-timeblock-db-insert-work-log
           date-str (plist-get log :title) end-str
           (org-timeblock-worklog--minutes-to-time le)
           (plist-get log :category-id) (plist-get log :source))))))
    ;; Insert the new entry
    (org-timeblock-db-insert-work-log date-str title start-str end-str nil "manual")
    (let ((hint (org-timeblock-category-auto-assign title)))
      (message "Inserted: %s (%s-%s)%s" title start-str end-str
               (if hint " [past category exists, use 'e' to assign]" "")))
    (deactivate-mark)
    (org-timeblock-worklog--refresh)))

;;; ---- Boundary adjustment ----

(defun org-timeblock-worklog--adjust-boundary (which delta)
  "Adjust WHICH (:start-time or :end-time) of entry at point by DELTA minutes."
  (let* ((entry (org-timeblock-display--entry-at-point))
         (log (org-timeblock-worklog--find-db-log-for-entry entry)))
    (unless log (user-error "No confirmed DB entry at point"))
    (let* ((date-str (org-timeblock-worklog--current-date-string))
           (id (plist-get log :id))
           (new-val (org-timeblock-worklog--time-add (plist-get log which) delta))
           (new-start (if (eq which :start-time) new-val (plist-get log :start-time)))
           (new-end (if (eq which :end-time) new-val (plist-get log :end-time))))
      (when (not (string< new-start new-end))
        (user-error "Invalid: %s-%s" new-start new-end))
      (when (org-timeblock-db-check-collision date-str new-start new-end id)
        (user-error "Time collision detected"))
      (org-timeblock-db-update-work-log id which new-val)
      (message "%s: %s-%s" (plist-get log :title) new-start new-end)
      (org-timeblock-worklog--refresh))))

(defun org-timeblock-worklog-adjust-start-earlier ()
  "Move start boundary 15 minutes earlier (expand)."
  (interactive)
  (org-timeblock-worklog--adjust-boundary :start-time -15))

(defun org-timeblock-worklog-adjust-start-later ()
  "Move start boundary 15 minutes later (shrink)."
  (interactive)
  (org-timeblock-worklog--adjust-boundary :start-time 15))

(defun org-timeblock-worklog-adjust-end-later ()
  "Move end boundary 15 minutes later (expand)."
  (interactive)
  (org-timeblock-worklog--adjust-boundary :end-time 15))

(defun org-timeblock-worklog-adjust-end-earlier ()
  "Move end boundary 15 minutes earlier (shrink)."
  (interactive)
  (org-timeblock-worklog--adjust-boundary :end-time -15))

;;; ---- Break management ----

(defun org-timeblock-worklog--shift-break (delta)
  "Shift the default break by DELTA minutes."
  (let* ((start-min (org-timeblock-worklog--time-to-minutes org-timeblock-worklog-break-start))
         (end-min (org-timeblock-worklog--time-to-minutes org-timeblock-worklog-break-end))
         (new-start-min (+ start-min delta))
         (new-end-min (+ end-min delta)))
    (when (or (< new-start-min 0) (> new-end-min 1440))
      (user-error "Break would go out of bounds"))
    (setq org-timeblock-worklog-break-start (org-timeblock-worklog--minutes-to-time new-start-min))
    (setq org-timeblock-worklog-break-end (org-timeblock-worklog--minutes-to-time new-end-min))
    (message "Break: %s-%s" org-timeblock-worklog-break-start org-timeblock-worklog-break-end)
    (org-timeblock-worklog--refresh)))

(defun org-timeblock-worklog-shift-break-1min-up ()
  "Shift break 1 minute earlier."
  (interactive)
  (org-timeblock-worklog--shift-break -1))

(defun org-timeblock-worklog-shift-break-1min-down ()
  "Shift break 1 minute later."
  (interactive)
  (org-timeblock-worklog--shift-break 1))

(defun org-timeblock-worklog-shift-break-5min-up ()
  "Shift break 5 minutes earlier."
  (interactive)
  (org-timeblock-worklog--shift-break -5))

(defun org-timeblock-worklog-shift-break-5min-down ()
  "Shift break 5 minutes later."
  (interactive)
  (org-timeblock-worklog--shift-break 5))

;;; ---- Date navigation ----

(defun org-timeblock-worklog--goto-date (date-str)
  "Navigate the display to DATE-STR (YYYY-MM-DD)."
  (when date-str
    (let ((display-date (org-timeblock-worklog--date-string-to-display-date date-str)))
      (when display-date
        (org-timeblock-display--render display-date)
        (message "Viewing: %s" date-str)))))

(defun org-timeblock-worklog-goto-next-date ()
  "Go to the next date with attendance records."
  (interactive)
  (let* ((current (org-timeblock-worklog--current-date-string))
         (next (org-timeblock-db-get-next-attendance-date current)))
    (if next
        (org-timeblock-worklog--goto-date next)
      (message "No next attendance date"))))

(defun org-timeblock-worklog-goto-prev-date ()
  "Go to the previous date with attendance records."
  (interactive)
  (let* ((current (org-timeblock-worklog--current-date-string))
         (prev (org-timeblock-db-get-prev-attendance-date current)))
    (if prev
        (org-timeblock-worklog--goto-date prev)
      (message "No previous attendance date"))))

(defun org-timeblock-worklog-goto-next-unconfirmed ()
  "Go to the next date with unconfirmed entries."
  (interactive)
  (let* ((current (org-timeblock-worklog--current-date-string))
         (next (org-timeblock-db-get-next-unconfirmed-date current)))
    (if next
        (org-timeblock-worklog--goto-date next)
      (message "No next unconfirmed date"))))

(defun org-timeblock-worklog-goto-prev-unconfirmed ()
  "Go to the previous date with unconfirmed entries."
  (interactive)
  (let* ((current (org-timeblock-worklog--current-date-string))
         (prev (org-timeblock-db-get-prev-unconfirmed-date current)))
    (if prev
        (org-timeblock-worklog--goto-date prev)
      (message "No previous unconfirmed date"))))

;;; ---- Past date view ----

(defun org-timeblock-worklog-view-past-date ()
  "View confirmed work logs for a past date in a dedicated buffer."
  (interactive)
  (let* ((date-str (read-string "Date (YYYY-MM-DD): "))
         (logs (org-timeblock-db-get-work-logs-by-date date-str))
         (buf (get-buffer-create "*Org Timeblock Past*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "=== Work Logs for %s ===\n\n" date-str))
        (if (null logs)
            (insert "(no confirmed entries)\n")
          (dolist (log logs)
            (insert (format "%s-%s  %s  [%s]\n"
                            (plist-get log :start-time)
                            (plist-get log :end-time)
                            (plist-get log :title)
                            (plist-get log :source)))))
        (goto-char (point-min))
        (special-mode)))
    (pop-to-buffer buf)))

;;; ---- Category summary ----

(defun org-timeblock-worklog--resolve-other-category-id ()
  "Resolve `org-timeblock-worklog-other-category' to a DB category ID.
If the category does not exist in the DB, create it automatically."
  (when org-timeblock-worklog-other-category
    (let* ((spec org-timeblock-worklog-other-category)
           (categories (org-timeblock-db-get-categories))
           (parts (split-string spec " / " t)))
      (or
       ;; Try to find existing
       (if (= (length parts) 2)
           (let* ((parent-name (nth 0 parts))
                  (child-name (nth 1 parts))
                  (parent (seq-find (lambda (c)
                                      (and (null (plist-get c :parent-id))
                                           (equal (plist-get c :name) parent-name)))
                                    categories)))
             (when parent
               (plist-get
                (seq-find (lambda (c)
                            (and (equal (plist-get c :parent-id) (plist-get parent :id))
                                 (equal (plist-get c :name) child-name)))
                          categories)
                :id)))
         (plist-get
          (seq-find (lambda (c) (equal (plist-get c :name) spec)) categories)
          :id))
       ;; Not found: create
       (if (= (length parts) 2)
           (let* ((parent-name (nth 0 parts))
                  (child-name (nth 1 parts))
                  (parent (seq-find (lambda (c)
                                      (and (null (plist-get c :parent-id))
                                           (equal (plist-get c :name) parent-name)))
                                    (org-timeblock-db-get-categories)))
                  (parent-id (or (when parent (plist-get parent :id))
                                 (org-timeblock-db-insert-category parent-name))))
             (org-timeblock-db-insert-category child-name parent-id))
         (org-timeblock-db-insert-category spec))))))

(defun org-timeblock-worklog--compute-summary (date-str)
  "Compute category summary for DATE-STR with trimming and Other filling.
Returns plist (:entries list :clock-in str :clock-out str :total-minutes int).
Work logs are trimmed to the clock-in/clock-out window.
Break time (minus work-log overlap) is shown as \"Break\".
Remaining gaps are attributed to the Other category."
  (org-timeblock-worklog--resolve-other-category-id)
  (let* ((attendance (org-timeblock-db-get-attendance date-str))
         (ci-str (when attendance (plist-get attendance :clock-in)))
         (co-str (when attendance (plist-get attendance :clock-out)))
         (ci-min (when ci-str (org-timeblock-worklog--time-to-minutes ci-str)))
         (co-min (when co-str (org-timeblock-worklog--time-to-minutes co-str)))
         (logs (org-timeblock-db-get-work-logs-by-date date-str))
         ;; Build category display name map
         (categories (org-timeblock-db-get-categories))
         (id-cat-map (make-hash-table :test 'equal))
         (cat-display (make-hash-table :test 'equal))
         (cat-minutes (make-hash-table :test 'equal))
         (cat-id-for-name (make-hash-table :test 'equal))
         (work-ranges nil))
    ;; Build maps
    (dolist (c categories)
      (puthash (plist-get c :id) c id-cat-map))
    (dolist (c categories)
      (let* ((name (plist-get c :name))
             (pid (plist-get c :parent-id))
             (parent (when pid (gethash pid id-cat-map))))
        (puthash (plist-get c :id)
                 (if parent (format "%s / %s" (plist-get parent :name) name) name)
                 cat-display)))
    ;; Process work logs: trim to window, accumulate per category
    (dolist (log logs)
      (let* ((ls (org-timeblock-worklog--time-to-minutes (plist-get log :start-time)))
             (le (org-timeblock-worklog--time-to-minutes (plist-get log :end-time)))
             (ts (if ci-min (max ls ci-min) ls))
             (te (if co-min (min le co-min) le))
             (mins (max 0 (- te ts))))
        (when (> mins 0)
          (push (cons ts te) work-ranges)
          (let* ((cid (plist-get log :category-id))
                 (cname (if cid
                            (or (gethash cid cat-display) "(uncategorized)")
                          "(uncategorized)")))
            (puthash cname (+ (gethash cname cat-minutes 0) mins) cat-minutes)
            (unless (gethash cname cat-id-for-name)
              (puthash cname cid cat-id-for-name))))))
    ;; Break: trimmed to window, added to work-ranges for Other calculation (not shown in summary)
    (when (and ci-min co-min)
      (let* ((bs (org-timeblock-worklog--time-to-minutes org-timeblock-worklog-break-start))
             (be (org-timeblock-worklog--time-to-minutes org-timeblock-worklog-break-end))
             (tbs (max bs ci-min))
             (tbe (min be co-min)))
        (when (> tbe tbs)
          (push (cons tbs tbe) work-ranges))))
    ;; Other: gaps in work window not covered by work logs or break
    (when (and ci-min co-min)
      (let* ((gaps (org-timeblock-worklog--subtract-ranges ci-min co-min work-ranges))
             (other-mins (apply #'+ (mapcar (lambda (g) (- (cdr g) (car g))) gaps))))
        (when (> other-mins 0)
          (let ((other-name (or org-timeblock-worklog-other-category "(other)"))
                (other-id (org-timeblock-worklog--resolve-other-category-id)))
            (puthash other-name
                     (+ (gethash other-name cat-minutes 0) other-mins)
                     cat-minutes)
            (puthash other-name other-id cat-id-for-name)))))
    ;; Return
    (let ((entries nil))
      (maphash (lambda (name mins)
                 (push (list :category-name name
                             :category-id (gethash name cat-id-for-name)
                             :total-minutes mins)
                       entries))
               cat-minutes)
      (list :entries (sort entries (lambda (a b) (> (plist-get a :total-minutes)
                                                    (plist-get b :total-minutes))))
            :clock-in ci-str
            :clock-out co-str
            :total-minutes (if (and ci-min co-min) (- co-min ci-min) 0)))))

(defun org-timeblock-worklog--format-summary (date-str result)
  "Format RESULT from `--compute-summary' for DATE-STR display."
  (let* ((entries (plist-get result :entries))
         (ci (plist-get result :clock-in))
         (co (plist-get result :clock-out))
         (total (plist-get result :total-minutes))
         (header (format "%s  %s-%s  Total: %02d:%02d"
                         date-str
                         (or ci "??:??") (or co "??:??")
                         (/ total 60) (mod total 60))))
    (concat header "\n"
            (mapconcat (lambda (s)
                         (let ((mins (plist-get s :total-minutes)))
                           (format "  %s: %02d:%02d"
                                   (plist-get s :category-name)
                                   (/ mins 60) (mod mins 60))))
                       entries "\n"))))

(defun org-timeblock-worklog-show-category-summary ()
  "Show category summary for the current display date.
Includes trimming to clock-in/clock-out and Other category for gaps."
  (interactive)
  (let* ((date-str (or (org-timeblock-worklog--current-date-string)
                       (format-time-string "%Y-%m-%d")))
         (result (org-timeblock-worklog--compute-summary date-str)))
    (if (plist-get result :entries)
        (message "%s" (org-timeblock-worklog--format-summary date-str result))
      (message "No data for %s" date-str))))

(defun org-timeblock-worklog-show-category-summary-for-date ()
  "Show category summary for a specified date."
  (interactive)
  (let* ((date-str (read-string "Date (YYYY-MM-DD): "))
         (result (org-timeblock-worklog--compute-summary date-str)))
    (if (plist-get result :entries)
        (message "%s" (org-timeblock-worklog--format-summary date-str result))
      (message "No data for %s" date-str))))

;;; ---- Programmatic summary access ----

(defun org-timeblock-worklog-get-summary (date-str)
  "Return summary for DATE-STR as a plist for programmatic use.
Result: (:entries list :clock-in str :clock-out str :total-minutes int).
Each entry in :entries has :category-name, :category-id, :total-minutes.
Break is excluded; gaps are attributed to the Other category."
  (org-timeblock-worklog--compute-summary date-str))

;;; ---- Alerts ----

(defun org-timeblock-worklog-check-unconfirmed ()
  "Check for unconfirmed entries and missing clock-in/out."
  (interactive)
  (let* ((date-str (org-timeblock-worklog--current-date-string))
         (attendance (org-timeblock-db-get-attendance date-str))
         (logs (org-timeblock-db-get-work-logs-by-date date-str))
         (warnings nil))
    (unless attendance
      (push (format "%s: No attendance record" date-str) warnings))
    (when attendance
      (unless (plist-get attendance :clock-in)
        (push (format "%s: Missing clock-in" date-str) warnings))
      (unless (plist-get attendance :clock-out)
        (push (format "%s: Missing clock-out" date-str) warnings)))
    (when (null logs)
      (push (format "%s: No confirmed work logs" date-str) warnings))
    (if warnings
        (message "Alerts:\n%s" (string-join (nreverse warnings) "\n"))
      (message "%s: All OK" date-str))))

;;; ---- Org-journal export ----

(defun org-timeblock-worklog-export-journal ()
  "Export confirmed work logs to an org-journal file."
  (interactive)
  (require 'org-journal)
  (let* ((date-str (org-timeblock-worklog--current-date-string))
         (logs (org-timeblock-db-get-work-logs-by-date date-str)))
    (when (null logs)
      (user-error "No work logs for %s" date-str))
    (let* ((year (string-to-number (substring date-str 0 4)))
           (month (string-to-number (substring date-str 5 7)))
           (day (string-to-number (substring date-str 8 10)))
           (time-obj (encode-time 0 0 0 day month year))
           (journal-dir (bound-and-true-p org-journal-dir))
           (file-format (bound-and-true-p org-journal-file-format))
           (file (expand-file-name
                  (format-time-string file-format time-obj)
                  journal-dir))
           (file-exists (file-exists-p file))
           (new-entries 0))
      ;; Create journal file if it doesn't exist
      (unless file-exists
        (let ((dir (file-name-directory file)))
          (unless (file-directory-p dir)
            (make-directory dir t)))
        (with-temp-file file
          (insert (format "* %04d/%02d/%02d\n" year month day))))
      ;; Insert entries
      (with-current-buffer (find-file-noselect file)
        ;; Find the level-1 heading and go to end of its subtree
        (goto-char (point-min))
        (let ((heading-found nil))
          (while (and (not heading-found) (not (eobp)))
            (when (looking-at "^\\* ")
              (setq heading-found t))
            (unless heading-found
              (forward-line 1)))
          (if heading-found
              (progn
                (org-end-of-subtree t)
                ;; Move past trailing whitespace to avoid adding extra newlines
                (when (looking-at "[ \t\n]*\\'")
                  (goto-char (match-beginning 0)))
                (unless (bolp) (insert "\n")))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))))
        (let ((insert-point (point)))
          (dolist (log logs)
            (let* ((heading (format "** %s %s"
                                    (plist-get log :start-time)
                                    (plist-get log :title))))
              ;; Check for duplicates
              (save-excursion
                (goto-char (point-min))
                (unless (search-forward heading nil t)
                  (goto-char insert-point)
                  (insert heading "\n")
                  (setq insert-point (point))
                  (setq new-entries (1+ new-entries)))))))
        ;; Normalize trailing whitespace to exactly one newline
        (goto-char (point-max))
        (when (re-search-backward "[^ \t\n]" nil t)
          (forward-char 1)
          (unless (= (point) (point-max))
            (delete-region (point) (point-max)))
          (insert "\n"))
        (let ((before-save-hook nil)
              (after-save-hook nil))
          (save-buffer)))
      (message "Exported %d entries to %s" new-entries file))))

;;; ---- Cleanup ----

(defun org-timeblock-worklog-delete-date ()
  "Delete all work logs for a specified date."
  (interactive)
  (let ((date-str (read-string "Date to delete (YYYY-MM-DD): ")))
    (when (y-or-n-p (format "Delete all work logs for %s? " date-str))
      (org-timeblock-db-delete-work-logs-by-date date-str)
      (message "Deleted all work logs for %s" date-str))))

(defun org-timeblock-worklog-delete-before-date ()
  "Delete all work logs before a specified date."
  (interactive)
  (let ((date-str (read-string "Delete logs before date (YYYY-MM-DD): ")))
    (when (y-or-n-p (format "Delete all work logs before %s? " date-str))
      (org-timeblock-db-delete-work-logs-before-date date-str)
      (message "Deleted all work logs before %s" date-str))))

;;; ---- Keybindings ----

(defun org-timeblock-worklog-setup-keybindings ()
  "Set up keybindings in `org-timeblock-display-mode-map'."
  ;; Remove legacy keybindings
  (define-key org-timeblock-display-mode-map (kbd "m") nil)
  (define-key org-timeblock-display-mode-map (kbd "i") nil)
  (define-key org-timeblock-display-mode-map (kbd "o") nil)
  (define-key org-timeblock-display-mode-map (kbd "s") nil)
  (define-key org-timeblock-display-mode-map (kbd "f") nil)
  (define-key org-timeblock-display-mode-map (kbd "t") nil)

  ;; Navigation
  (define-key org-timeblock-display-mode-map (kbd "n") #'next-line)
  (define-key org-timeblock-display-mode-map (kbd "p") #'previous-line)

  ;; Confirm / Cancel / Category
  (define-key org-timeblock-display-mode-map (kbd "RET") #'org-timeblock-worklog-confirm)
  (define-key org-timeblock-display-mode-map (kbd "C") #'org-timeblock-worklog-confirm-with-category)
  (define-key org-timeblock-display-mode-map (kbd "e") #'org-timeblock-worklog-set-category)
  (define-key org-timeblock-display-mode-map (kbd "x") #'org-timeblock-worklog-cancel)

  ;; Insert (cursor or region)
  (define-key org-timeblock-display-mode-map (kbd "a") #'org-timeblock-worklog-insert)

  ;; Move entire entry
  (define-key org-timeblock-display-mode-map (kbd "M-p") #'org-timeblock-worklog-move-up)
  (define-key org-timeblock-display-mode-map (kbd "M-n") #'org-timeblock-worklog-move-down)

  ;; Boundary adjustment ([ ] expand, { } shrink)
  (define-key org-timeblock-display-mode-map (kbd "[") #'org-timeblock-worklog-adjust-start-earlier)
  (define-key org-timeblock-display-mode-map (kbd "]") #'org-timeblock-worklog-adjust-end-later)
  (define-key org-timeblock-display-mode-map (kbd "{") #'org-timeblock-worklog-adjust-start-later)
  (define-key org-timeblock-display-mode-map (kbd "}") #'org-timeblock-worklog-adjust-end-earlier)

  ;; Break
  (define-key org-timeblock-display-mode-map (kbd "b p") #'org-timeblock-worklog-shift-break-1min-up)
  (define-key org-timeblock-display-mode-map (kbd "b n") #'org-timeblock-worklog-shift-break-1min-down)
  (define-key org-timeblock-display-mode-map (kbd "b P") #'org-timeblock-worklog-shift-break-5min-up)
  (define-key org-timeblock-display-mode-map (kbd "b N") #'org-timeblock-worklog-shift-break-5min-down)

  ;; Date navigation
  (define-key org-timeblock-display-mode-map (kbd ">") #'org-timeblock-worklog-goto-next-date)
  (define-key org-timeblock-display-mode-map (kbd "<") #'org-timeblock-worklog-goto-prev-date)
  (define-key org-timeblock-display-mode-map (kbd "M->") #'org-timeblock-worklog-goto-next-unconfirmed)
  (define-key org-timeblock-display-mode-map (kbd "M-<") #'org-timeblock-worklog-goto-prev-unconfirmed)

  ;; Refresh
  (define-key org-timeblock-display-mode-map (kbd "R") #'org-timeblock-display-refresh)

  ;; Other
  (define-key org-timeblock-display-mode-map (kbd "v") #'org-timeblock-worklog-view-past-date)
  (define-key org-timeblock-display-mode-map (kbd "S") #'org-timeblock-worklog-show-category-summary)
  (define-key org-timeblock-display-mode-map (kbd "c") #'org-timeblock-worklog-show-category-summary-for-date)
  (define-key org-timeblock-display-mode-map (kbd "!") #'org-timeblock-worklog-check-unconfirmed)
  (define-key org-timeblock-display-mode-map (kbd "J") #'org-timeblock-worklog-export-journal)
  (define-key org-timeblock-display-mode-map (kbd "L") #'org-timeblock-category-list))

(with-eval-after-load 'org-timeblock-display
  (org-timeblock-worklog-setup-keybindings)

  ;; Global clock-in/out keybindings
  (global-set-key (kbd "C-c i") #'org-timeblock-worklog-clock-in)
  (global-set-key (kbd "C-c o") #'org-timeblock-worklog-clock-out)
  (global-set-key (kbd "C-c I") #'org-timeblock-worklog-clock-in-date)
  (global-set-key (kbd "C-c O") #'org-timeblock-worklog-clock-out-date)

  (when (require 'hydra nil t)
    (defhydra org-timeblock-display-help (:color blue :hint nil)
      "
 Confirm  _RET_ confirm  _C_ w/ category  _e_ set category  _x_ cancel
 Insert   _a_ add (cursor/region)
 Adjust   _[_ start←  _{_ start→  _]_ end→  _}_ end←  _M-p_ move↑  _M-n_ move↓
 Nav      _n_/_p_ ↑↓  _TAB_ next  _<backtab>_ prev  _>_ date→  _<_ date←  _M->_ unc→  _M-<_ unc←
 View     _v_ past  _S_ summary  _c_ date summ  _L_ categories  _!_ alerts  _J_ journal
 Other    _R_ refresh  b p/P n/N break±1/5  _q_ quit
"
      ("RET" org-timeblock-worklog-confirm)
      ("C" org-timeblock-worklog-confirm-with-category)
      ("e" org-timeblock-worklog-set-category)
      ("x" org-timeblock-worklog-cancel)
      ("R" org-timeblock-display-refresh)
      ("n" next-line)
      ("p" previous-line)
      ("a" org-timeblock-worklog-insert)
      ("[" org-timeblock-worklog-adjust-start-earlier)
      ("]" org-timeblock-worklog-adjust-end-later)
      ("{" org-timeblock-worklog-adjust-start-later)
      ("}" org-timeblock-worklog-adjust-end-earlier)
      ("M-p" org-timeblock-worklog-move-up)
      ("M-n" org-timeblock-worklog-move-down)
      ("TAB" org-timeblock-display-next-event)
      ("<backtab>" org-timeblock-display-prev-event)
      (">" org-timeblock-worklog-goto-next-date)
      ("<" org-timeblock-worklog-goto-prev-date)
      ("M->" org-timeblock-worklog-goto-next-unconfirmed)
      ("M-<" org-timeblock-worklog-goto-prev-unconfirmed)
      ("v" org-timeblock-worklog-view-past-date)
      ("S" org-timeblock-worklog-show-category-summary)
      ("c" org-timeblock-worklog-show-category-summary-for-date)
      ("!" org-timeblock-worklog-check-unconfirmed)
      ("J" org-timeblock-worklog-export-journal)
      ("L" org-timeblock-category-list)
      ("q" nil))
    (define-key org-timeblock-display-mode-map (kbd "?") #'org-timeblock-display-help/body)))

(provide 'org-timeblock-worklog)

;;; org-timeblock-worklog.el ends here
