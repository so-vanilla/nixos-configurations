;;; org-timeblock-display.el --- Timeblock sidebar display -*- lexical-binding: t; -*-

;;; Commentary:
;; Display time blocks in a left sidebar window using block characters.
;; Replaces org-agenda time grid with a visual 15-min/row representation.

;;; Code:

(require 'org-agenda)

(declare-function org-timeblock-db-get-work-logs-by-date "org-timeblock-db" (date))
(declare-function org-timeblock-db-get-attendance "org-timeblock-db" (date))
(defvar org-timeblock-worklog-break-start)
(defvar org-timeblock-worklog-break-end)
(defvar org-timeblock-worklog-break-title)

;; --- Customization ---

(defgroup org-timeblock-display nil
  "Timeblock sidebar display."
  :group 'org
  :prefix "org-timeblock-display-")

(defcustom org-timeblock-display-start-hour 8
  "Start hour of the time grid."
  :type 'integer
  :group 'org-timeblock-display)

(defcustom org-timeblock-display-end-hour 19
  "End hour of the time grid."
  :type 'integer
  :group 'org-timeblock-display)

(defcustom org-timeblock-display-block-width 4
  "Width of block characters in columns."
  :type 'integer
  :group 'org-timeblock-display)

(defcustom org-timeblock-display-buffer-name "*Org Timeblock*"
  "Name of the timeblock display buffer."
  :type 'string
  :group 'org-timeblock-display)

;; --- Color definitions ---

(defconst org-timeblock-display--nocategory-fg "#9ca0b0"
  "Foreground for blocks without category (overlay0 equivalent).")

(defconst org-timeblock-display--rotation-colors
  '(blue mauve green peach pink teal sapphire lavender red yellow flamingo rosewater)
  "Catppuccin color names for sequential entry coloring.")

(defconst org-timeblock-display--latte-fallback
  '((blue . "#1e66f5") (mauve . "#8839ef") (green . "#40a02b") (peach . "#fe640b")
    (pink . "#ea76cb") (teal . "#179299") (sapphire . "#209fb5") (lavender . "#7287fd")
    (overlay0 . "#9ca0b0") (surface1 . "#bcc0cc") (red . "#d20f39")
    (mantle . "#e6e9ef") (base . "#eff1f5"))
  "Catppuccin Latte fallback hex values.")

;; --- Buffer-local variables ---

(defvar-local org-timeblock-display--current-date nil
  "Current display date as (MONTH DAY YEAR).")

(defvar-local org-timeblock-display--line-map nil
  "Vector of 44 elements, each an entry plist or nil for the corresponding row.")

(defvar org-timeblock-display--timer nil
  "Timer for periodic now-indicator refresh.")

(defvar-local org-timeblock-display--last-update nil
  "Timestamp string of the last render (HH:MM:SS).")

;; --- Color utilities ---

(defun org-timeblock-display--get-color (name)
  "Get color hex string for catppuccin color NAME.
Uses `catppuccin-get-color' if available, otherwise Latte fallback."
  (if (fboundp 'catppuccin-get-color)
      (catppuccin-get-color name)
    (alist-get name org-timeblock-display--latte-fallback)))

(defun org-timeblock-display--face-from-color (hex-color)
  "Return face for block characters with HEX-COLOR foreground."
  `(:foreground ,hex-color))

(defun org-timeblock-display--bg-face-from-color (hex-color)
  "Return face for right side with subtle HEX-COLOR background tint."
  (let* ((base (or (org-timeblock-display--get-color 'base) "#eff1f5"))
         (bg (org-timeblock-display--blend-color hex-color base 0.12)))
    `(:background ,bg)))

(defun org-timeblock-display--blend-color (color base ratio)
  "Blend COLOR with BASE at RATIO (0.0=base, 1.0=color).
COLOR and BASE are hex strings like \"#1e66f5\"."
  (let* ((cr (string-to-number (substring color 1 3) 16))
         (cg (string-to-number (substring color 3 5) 16))
         (cb (string-to-number (substring color 5 7) 16))
         (br (string-to-number (substring base 1 3) 16))
         (bg (string-to-number (substring base 3 5) 16))
         (bb (string-to-number (substring base 5 7) 16)))
    (format "#%02x%02x%02x"
            (round (+ (* cr ratio) (* br (- 1.0 ratio))))
            (round (+ (* cg ratio) (* bg (- 1.0 ratio))))
            (round (+ (* cb ratio) (* bb (- 1.0 ratio)))))))

(defun org-timeblock-display--build-color-map (entries)
  "Assign sequential catppuccin colors to ENTRIES for adjacency differentiation.
Returns alist of (entry . hex-color-string)."
  (let ((palette org-timeblock-display--rotation-colors)
        (len (length org-timeblock-display--rotation-colors))
        (index 0))
    (mapcar (lambda (entry)
              (let ((hex (org-timeblock-display--get-color (nth (mod index len) palette))))
                (setq index (1+ index))
                (cons entry hex)))
            entries)))

;; --- Time utilities ---

(defun org-timeblock-display--total-rows ()
  "Total number of rows in the grid."
  (* (- org-timeblock-display-end-hour org-timeblock-display-start-hour) 4))

(defun org-timeblock-display--minutes-to-row (minutes)
  "Convert absolute MINUTES (from midnight) to grid row index.
Row 0 = start-hour:00."
  (/ (- minutes (* org-timeblock-display-start-hour 60)) 15))

(defun org-timeblock-display--row-to-minutes (row)
  "Convert grid ROW index to absolute minutes from midnight."
  (+ (* org-timeblock-display-start-hour 60) (* row 15)))

(defun org-timeblock-display--now-row ()
  "Return the current row index for now, or nil if outside grid."
  (let* ((time (decode-time))
         (minutes (+ (* (nth 2 time) 60) (nth 1 time)))
         (row (org-timeblock-display--minutes-to-row minutes)))
    (when (and (>= row 0) (< row (org-timeblock-display--total-rows)))
      row)))

(defun org-timeblock-display--time-string-to-minutes (time-str)
  "Convert TIME-STR like \"09:30\" to minutes from midnight."
  (when (and time-str (string-match "\\`\\([0-9]+\\):\\([0-9]+\\)\\'" time-str))
    (+ (* (string-to-number (match-string 1 time-str)) 60)
       (string-to-number (match-string 2 time-str)))))

(defun org-timeblock-display--minutes-to-time-string (minutes)
  "Convert MINUTES from midnight to \"HH:MM\" string."
  (format "%02d:%02d" (/ minutes 60) (mod minutes 60)))

;; --- Date conversion ---

(defun org-timeblock-display--date-to-string (date)
  "Convert DATE (MONTH DAY YEAR) to \"YYYY-MM-DD\" string."
  (format "%04d-%02d-%02d" (nth 2 date) (nth 0 date) (nth 1 date)))

;; --- Data retrieval ---

(defun org-timeblock-display--get-org-entries (date)
  "Get org-agenda entries for DATE as (MONTH DAY YEAR).
Returns list of plists (:title :start-minutes :end-minutes :confirmed-p nil)."
  (org-compile-prefix-format 'agenda)
  (let* ((files (org-agenda-files nil 'ifmode))
         (entries nil))
    (dolist (file files)
      (dolist (entry (org-agenda-get-day-entries file date :scheduled :timestamp :deadline))
        (let* ((time-of-day (get-text-property 0 'time-of-day entry))
               (duration (get-text-property 0 'duration entry))
               (txt (get-text-property 0 'txt entry)))
          (when (and time-of-day (> time-of-day 0)
                     ;; Exclude entries with TODO keywords (TODO, DONE, etc.)
                     (null (get-text-property 0 'todo-state entry)))
            (let* ((start-h (/ time-of-day 100))
                   (start-m (mod time-of-day 100))
                   (start-minutes (+ (* start-h 60) start-m))
                   (dur (or duration 60.0))
                   (end-minutes (+ start-minutes (round dur)))
                   (title (if txt
                              (replace-regexp-in-string "\\`[ \t:]+" "" (substring-no-properties txt))
                            "???")))
              (push (list :title title
                          :start-minutes start-minutes
                          :end-minutes end-minutes
                          :confirmed-p nil
                          :source 'org)
                    entries))))))
    ;; Deduplicate: Google Calendar sync may create duplicate entries
    (let ((seen (make-hash-table :test 'equal))
          (result nil))
      (dolist (entry (nreverse entries))
        (let ((key (format "%s@%d" (plist-get entry :title) (plist-get entry :start-minutes))))
          (unless (gethash key seen)
            (puthash key t seen)
            (push entry result))))
      (nreverse result))))

(defun org-timeblock-display--merge-entries (date)
  "Merge org entries and DB work logs for DATE.
DB confirmed entries override org entries with same title and overlapping time."
  (let* ((org-entries (org-timeblock-display--get-org-entries date))
         (date-str (org-timeblock-display--date-to-string date))
         (work-logs (when (fboundp 'org-timeblock-db-get-work-logs-by-date)
                      (org-timeblock-db-get-work-logs-by-date date-str)))
         (default-break (when (and (boundp 'org-timeblock-worklog-break-start)
                                  (boundp 'org-timeblock-worklog-break-end)
                                  org-timeblock-worklog-break-start
                                  org-timeblock-worklog-break-end)
                          (list :start-time org-timeblock-worklog-break-start
                                :end-time org-timeblock-worklog-break-end)))
         (confirmed nil))
    ;; Convert work logs to entry plists
    (dolist (log work-logs)
      (let ((start (org-timeblock-display--time-string-to-minutes (plist-get log :start-time)))
            (end (org-timeblock-display--time-string-to-minutes (plist-get log :end-time))))
        (when start
          (let ((gap-fill (null end))
                (effective-end (or end
                                   ;; Gap-fill: extend to current time or at least 15 min
                                   (let* ((now (decode-time))
                                          (now-min (+ (* (nth 2 now) 60) (nth 1 now))))
                                     (max (+ start 15) now-min)))))
            (push (list :title (or (plist-get log :title) "Work")
                        :start-minutes start
                        :end-minutes effective-end
                        :confirmed-p t
                        :source 'db
                        :category-id (plist-get log :category-id)
                        :gap-fill-p gap-fill)
                confirmed)))))
    ;; Add default break as confirmed
    (when default-break
      (let ((start (org-timeblock-display--time-string-to-minutes (plist-get default-break :start-time)))
            (end (org-timeblock-display--time-string-to-minutes (plist-get default-break :end-time))))
        (when (and start end)
          (push (list :title (or org-timeblock-worklog-break-title "Break")
                      :start-minutes start
                      :end-minutes end
                      :confirmed-p t
                      :source 'break)
                confirmed))))
    ;; Filter org entries: remove if same title overlaps a confirmed entry
    (let ((filtered-org
           (seq-remove
            (lambda (org-entry)
              (seq-some
               (lambda (conf)
                 (and (equal (plist-get org-entry :title) (plist-get conf :title))
                      (< (plist-get org-entry :start-minutes) (plist-get conf :end-minutes))
                      (> (plist-get org-entry :end-minutes) (plist-get conf :start-minutes))))
               confirmed))
            org-entries)))
      ;; Merge and sort by start-minutes
      (sort (append confirmed filtered-org)
            (lambda (a b)
              (< (plist-get a :start-minutes) (plist-get b :start-minutes)))))))

;; --- Rendering ---

(defun org-timeblock-display--block-char (row entry)
  "Determine block character for ROW given ENTRY plist.
Returns one of: full-block, lower-half, upper-half."
  (let* ((start (plist-get entry :start-minutes))
         (end (plist-get entry :end-minutes))
         (row-start (org-timeblock-display--row-to-minutes row))
         (row-end (+ row-start 15))
         (starts-mid (and (> start row-start) (< start row-end)))
         (ends-mid (and (> end row-start) (< end row-end))))
    (cond
     (starts-mid ?▄)  ; event starts mid-row
     (ends-mid ?▀)    ; event ends mid-row
     (t ?█))))         ; event covers full row

(defun org-timeblock-display--entry-covers-row-p (entry row)
  "Return non-nil if ENTRY covers ROW (even partially)."
  (let* ((start (plist-get entry :start-minutes))
         (end (plist-get entry :end-minutes))
         (row-start (org-timeblock-display--row-to-minutes row))
         (row-end (+ row-start 15)))
    (and (< start row-end) (> end row-start))))

(defun org-timeblock-display--format-time-range (entry)
  "Format time range string for ENTRY.
Confirmed: \"HH:MM - HH:MM\", unconfirmed: \"(HH:MM - HH:MM)\",
gap-fill in progress: \"(HH:MM -    )\"."
  (let ((start-str (org-timeblock-display--minutes-to-time-string
                    (plist-get entry :start-minutes)))
        (confirmed-p (plist-get entry :confirmed-p))
        (gap-fill-p (plist-get entry :gap-fill-p)))
    (cond
     (gap-fill-p
      (format "(%s -    )" start-str))
     (confirmed-p
      (format "%s - %s" start-str
              (org-timeblock-display--minutes-to-time-string
               (plist-get entry :end-minutes))))
     (t
      (format "(%s - %s)" start-str
              (org-timeblock-display--minutes-to-time-string
               (plist-get entry :end-minutes)))))))

(defun org-timeblock-display--render-line (row entries color-map now-row)
  "Render a single line for ROW given ENTRIES and COLOR-MAP.
NOW-ROW is current time row or nil."
  (let* ((total-width 28)
         (row-minutes (org-timeblock-display--row-to-minutes row))
         (hour (/ row-minutes 60))
         (minute (mod row-minutes 60))
         (time-label (if (= minute 0)
                         (format "%02d" hour)
                       "  "))
         (time-face `(:foreground ,(org-timeblock-display--get-color 'surface1)))
         (now-p (and now-row (= row now-row)))
         ;; Find entry covering this row
         (active-entry (seq-find
                        (lambda (e) (org-timeblock-display--entry-covers-row-p e row))
                        entries))
         (block-width org-timeblock-display-block-width)
         (line-parts nil))
    ;; Now indicator or time label (3 chars: "08 " or "◀  " or "   ")
    (let ((label-str
           (cond
            (now-p
             (let ((now-str (propertize "◀" 'face `(:foreground ,(org-timeblock-display--get-color 'red)))))
               (concat now-str (make-string (- 2 (string-width "◀")) ?\s) " ")))
            ((not (string-blank-p time-label))
             (concat (propertize time-label 'face time-face) " "))
            (t
             "   "))))
      (push label-str line-parts))
    ;; Block characters + right side content
    (if active-entry
        (let* ((char (org-timeblock-display--block-char row active-entry))
               (hex-color (or (cdr (assq active-entry color-map)) "#7287fd"))
               (has-category (or (plist-get active-entry :category-id)
                                 (eq (plist-get active-entry :source) 'break)))
               (block-fg (if has-category
                             hex-color
                           org-timeblock-display--nocategory-fg))
               (face (org-timeblock-display--face-from-color block-fg))
               (block-str (propertize (make-string block-width char) 'face face))
               ;; Determine if this is the start row
               (start-min (plist-get active-entry :start-minutes))
               (is-start-row (and (>= start-min row-minutes)
                                  (< start-min (+ row-minutes 15))))
               ;; Count consecutive rows this entry covers after start
               (entry-rows 0)
               (right-text ""))
          ;; Count how many rows this entry spans from start
          (when is-start-row
            (let ((r row))
              (while (and (< r (org-timeblock-display--total-rows))
                          (org-timeblock-display--entry-covers-row-p active-entry r))
                (setq entry-rows (1+ entry-rows))
                (setq r (1+ r)))))
          ;; Determine right-side text
          (cond
           ;; Start row: show title
           (is-start-row
            (let* ((title (plist-get active-entry :title))
                   (time-range (org-timeblock-display--format-time-range active-entry))
                   (space-after-block (- total-width 3 block-width))
                   ;; If entry spans 3+ rows, put time on next row
                   (show-time-here (<= entry-rows 2)))
              (if show-time-here
                  ;; Title + time on same line
                  (let* ((combined (concat " " title " " time-range))
                         (avail space-after-block))
                    (setq right-text (truncate-string-to-width combined avail 0 ?\s)))
                ;; Title only on this line
                (let ((avail space-after-block))
                  (setq right-text (truncate-string-to-width (concat " " title) avail 0 ?\s))))))
           ;; Row after start in long events: show time range if start row + 1
           ((let* ((prev-row (1- row)))
              (and (>= prev-row 0)
                   (let ((prev-start-min (plist-get active-entry :start-minutes))
                         (prev-row-min (org-timeblock-display--row-to-minutes prev-row)))
                     (and (>= prev-start-min prev-row-min)
                          (< prev-start-min (+ prev-row-min 15))
                          ;; Ensure entry spans 3+ rows from start
                          (let ((span 0) (r prev-row))
                            (while (and (< r (org-timeblock-display--total-rows))
                                        (org-timeblock-display--entry-covers-row-p active-entry r))
                              (setq span (1+ span))
                              (setq r (1+ r)))
                            (>= span 3))))))
            (let* ((time-range (org-timeblock-display--format-time-range active-entry))
                   (space-after-block (- total-width 3 block-width)))
              (setq right-text (truncate-string-to-width (concat " " time-range) space-after-block 0 ?\s)))))
          ;; Pad right text and apply right-side background
          (let* ((right-width (- total-width 3 block-width))
                 (right-face (org-timeblock-display--bg-face-from-color hex-color))
                 (padded-right (if (> (string-width right-text) 0)
                                   right-text
                                 (make-string right-width ?\s))))
            (push block-str line-parts)
            (push (propertize padded-right 'face right-face) line-parts)))
      ;; No active entry - empty row
      (let* ((empty-block (propertize (make-string block-width ?\s)
                                      'face `(:background ,(org-timeblock-display--get-color 'mantle))))
             (empty-right (make-string (- total-width 3 block-width) ?\s)))
        (push (concat empty-block empty-right) line-parts)))
    ;; Store in line-map
    (aset org-timeblock-display--line-map row active-entry)
    ;; Build final line with pixel-width compensation
    (let* ((line (apply #'concat (nreverse line-parts)))
           (target-px (* total-width (string-pixel-width " ")))
           (actual-px (string-pixel-width line))
           (diff (- target-px actual-px)))
      (if (> diff 0)
          ;; Append pixel-precise padding to compensate CJK width gap
          (let ((last-face (get-text-property (1- (length line)) 'face line)))
            (concat line (propertize " " 'display `(space :width (,diff))
                                     'face last-face)))
        line))))

(defun org-timeblock-display--render (date)
  "Render the full timeblock grid for DATE into the current buffer."
  (let* ((inhibit-read-only t)
         (saved-line (1- (line-number-at-pos)))
         (entries (org-timeblock-display--merge-entries date))
         (color-map (org-timeblock-display--build-color-map entries))
         (total-rows (org-timeblock-display--total-rows))
         (now-row (org-timeblock-display--now-row)))
    (setq org-timeblock-display--current-date date)
    (setq org-timeblock-display--line-map (make-vector total-rows nil))
    (erase-buffer)
    (dotimes (row total-rows)
      (insert (org-timeblock-display--render-line row entries color-map now-row))
      (unless (= row (1- total-rows))
        (insert "\n")))
    (setq org-timeblock-display--last-update (format-time-string "%H:%M:%S"))
    (force-mode-line-update)
    (goto-char (point-min))
    (forward-line (min saved-line (1- total-rows)))))

;; --- Window management ---

(defun org-timeblock-display-show (&optional date)
  "Show the timeblock sidebar for DATE (default today).
DATE is (MONTH DAY YEAR)."
  (interactive)
  (let* ((date (or date (let ((now (decode-time)))
                          (list (nth 4 now) (nth 3 now) (nth 5 now)))))
         (buf (get-buffer-create org-timeblock-display-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'org-timeblock-display-mode)
        (org-timeblock-display-mode))
      (org-timeblock-display--render date))
    (display-buffer-in-side-window buf
                                   '((side . left)
                                     (slot . 1)
                                     (window-width . 28)
                                     (dedicated . t)
                                     (window-parameters . ((no-delete-other-windows . t)))))
    (org-timeblock-display--adjust-side-windows)
    (org-timeblock-display--start-timer)
    buf))

(defun org-timeblock-display-close ()
  "Close the timeblock sidebar."
  (interactive)
  (org-timeblock-display--stop-timer)
  (when-let ((win (get-buffer-window org-timeblock-display-buffer-name t)))
    (delete-window win)))

(defun org-timeblock-display-toggle (&optional date)
  "Toggle the timeblock sidebar for DATE."
  (interactive)
  (if (get-buffer-window org-timeblock-display-buffer-name t)
      (org-timeblock-display-close)
    (org-timeblock-display-show date)))

(defun org-timeblock-display--adjust-side-windows ()
  "Adjust side window heights so aide gets 1/3 and timeblock gets 2/3.
Only acts when both windows are visible."
  (let ((aide-win (seq-find (lambda (w)
                              (and (window-parameter w 'window-side)
                                   (eq (window-parameter w 'window-slot) 0)))
                            (window-list)))
        (tb-win (get-buffer-window org-timeblock-display-buffer-name t)))
    (when (and aide-win tb-win
              (window-live-p aide-win)
              (window-live-p tb-win))
      (let* ((total-height (+ (window-height aide-win) (window-height tb-win)))
             (aide-target (max 3 (/ total-height 3)))
             (aide-delta (- aide-target (window-height aide-win))))
        (unless (= aide-delta 0)
          (ignore-errors
            (window-resize aide-win aide-delta nil t)))))))

;; --- Refresh / Timer ---

(defun org-timeblock-display-refresh (&optional date)
  "Refresh the timeblock display for DATE (or current date)."
  (interactive)
  (when-let ((buf (get-buffer org-timeblock-display-buffer-name)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((date (or date org-timeblock-display--current-date)))
          (when date
            (org-timeblock-display--render date)))))))

(defun org-timeblock-display--start-timer ()
  "Start the 60-second refresh timer for now indicator."
  (org-timeblock-display--stop-timer)
  (setq org-timeblock-display--timer
        (run-with-timer 60 60 #'org-timeblock-display-refresh)))

(defun org-timeblock-display--stop-timer ()
  "Stop the refresh timer."
  (when (timerp org-timeblock-display--timer)
    (cancel-timer org-timeblock-display--timer)
    (setq org-timeblock-display--timer nil)))

;; --- Cursor navigation ---

(defun org-timeblock-display--entry-at-point ()
  "Return the entry plist at the current cursor row, or nil."
  (when org-timeblock-display--line-map
    (let ((row (1- (line-number-at-pos))))
      (when (and (>= row 0) (< row (length org-timeblock-display--line-map)))
        (aref org-timeblock-display--line-map row)))))

(defun org-timeblock-display-next-event ()
  "Move cursor to the start of the next event."
  (interactive)
  (when org-timeblock-display--line-map
    (let* ((current-row (1- (line-number-at-pos)))
           (total (length org-timeblock-display--line-map))
           (current-entry (when (and (>= current-row 0) (< current-row total))
                            (aref org-timeblock-display--line-map current-row)))
           (found nil))
      ;; Skip past current entry
      (let ((row (1+ current-row)))
        (while (and (< row total) (not found))
          (let ((entry (aref org-timeblock-display--line-map row)))
            (when (and entry (not (eq entry current-entry)))
              ;; Found a different entry; check if this is its start row
              (let* ((start-min (plist-get entry :start-minutes))
                     (row-min (org-timeblock-display--row-to-minutes row)))
                (when (and (>= start-min row-min)
                           (< start-min (+ row-min 15)))
                  (setq found row)))))
          (setq row (1+ row))))
      (when found
        (goto-char (point-min))
        (forward-line found)))))

(defun org-timeblock-display-prev-event ()
  "Move cursor to the start of the previous event."
  (interactive)
  (when org-timeblock-display--line-map
    (let* ((current-row (1- (line-number-at-pos)))
           (total (length org-timeblock-display--line-map))
           (current-entry (when (and (>= current-row 0) (< current-row total))
                            (aref org-timeblock-display--line-map current-row)))
           (found nil))
      ;; Move backward, skip current entry first
      (let ((row (1- current-row)))
        ;; Skip rows of current entry
        (while (and (>= row 0)
                    (eq (aref org-timeblock-display--line-map row) current-entry))
          (setq row (1- row)))
        ;; Now find the start of the previous entry
        (when (>= row 0)
          (let ((target-entry (aref org-timeblock-display--line-map row)))
            (if (null target-entry)
                ;; In empty space, scan back for an entry
                (progn
                  (while (and (>= row 0)
                              (null (aref org-timeblock-display--line-map row)))
                    (setq row (1- row)))
                  (when (>= row 0)
                    (setq target-entry (aref org-timeblock-display--line-map row))
                    ;; Find start of this entry
                    (while (and (> row 0)
                                (eq (aref org-timeblock-display--line-map (1- row)) target-entry))
                      (setq row (1- row)))
                    (setq found row)))
              ;; In an entry, find its start
              (while (and (> row 0)
                          (eq (aref org-timeblock-display--line-map (1- row)) target-entry))
                (setq row (1- row)))
              (setq found row)))))
      (when found
        (goto-char (point-min))
        (forward-line found)))))

;; --- Major mode ---

(defvar org-timeblock-display-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "TAB") #'org-timeblock-display-next-event)
    (define-key map (kbd "<tab>") #'org-timeblock-display-next-event)
    (define-key map (kbd "S-TAB") #'org-timeblock-display-prev-event)
    (define-key map (kbd "<backtab>") #'org-timeblock-display-prev-event)
    (define-key map (kbd "q") #'org-timeblock-display-close)
    map)
  "Keymap for `org-timeblock-display-mode'.")

(defun org-timeblock-display--build-mode-line ()
  "Build mode-line content for timeblock buffer."
  (let* ((doom-p (bound-and-true-p doom-modeline-mode))
         (name-face (if doom-p 'doom-modeline-buffer-major-mode 'mode-line-buffer-id))
         (update-face (if doom-p 'doom-modeline-info 'shadow))
         (update-str (or org-timeblock-display--last-update "")))
    (list " "
          (propertize "Timeblock" 'face name-face)
          "  "
          (propertize update-str 'face update-face))))

(define-derived-mode org-timeblock-display-mode special-mode "Timeblock"
  "Major mode for org-timeblock sidebar display.
\\{org-timeblock-display-mode-map}"
  (setq-local buffer-read-only t)
  (setq-local truncate-lines t)
  (setq-local cursor-type nil)
  ;; Disable undo
  (setq-local buffer-undo-list t)
  (define-key (current-local-map) [remap undo] #'ignore)
  ;; Custom mode-line with last-update
  (setq-local mode-line-format '(:eval (org-timeblock-display--build-mode-line))))

(provide 'org-timeblock-display)

;;; org-timeblock-display.el ends here
