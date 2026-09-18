;;; org-timeblock-db.el --- SQLite database layer for org-timeblock -*- lexical-binding: t; -*-

;;; Commentary:
;; Provides SQLite database operations for org-timeblock.
;; Manages work_logs, categories, attendance, title_category_map,
;; default_break, and schema versioning.

;;; Code:

(defgroup org-timeblock-db nil
  "Database settings for org-timeblock."
  :group 'org-timeblock
  :prefix "org-timeblock-db-")

(defcustom org-timeblock-db-directory "~/.emacs.d/org-timeblock"
  "Directory where org-timeblock database files are stored."
  :type 'directory
  :group 'org-timeblock-db)

(defvar org-timeblock-db--connection nil
  "Current SQLite database connection.")

(defconst org-timeblock-db--schema-version 2
  "Current schema version.")

(defconst org-timeblock-db--schema-sql
  "CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER NOT NULL,
    applied_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    parent_id INTEGER,
    color TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL,
    UNIQUE(name, parent_id)
);

CREATE TABLE IF NOT EXISTS work_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    title TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    category_id INTEGER,
    source TEXT NOT NULL DEFAULT 'manual',
    created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
    CHECK (start_time < end_time)
);
CREATE INDEX IF NOT EXISTS idx_work_logs_date ON work_logs(date);
CREATE INDEX IF NOT EXISTS idx_work_logs_date_time ON work_logs(date, start_time, end_time);

CREATE TABLE IF NOT EXISTS title_category_map (
    title TEXT PRIMARY KEY,
    category_id INTEGER NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS attendance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE,
    clock_in TEXT,
    clock_out TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS default_break (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    start_time TEXT NOT NULL DEFAULT '12:00',
    end_time TEXT NOT NULL DEFAULT '13:00',
    CHECK (start_time < end_time)
);
INSERT OR IGNORE INTO default_break (id) VALUES (1);
INSERT INTO schema_version (version) VALUES (2);"
  "SQL schema for org-timeblock database.")

;;; ---- Connection management ----

(defun org-timeblock-db--db-path ()
  "Return the full path to the database file."
  (expand-file-name "timeblock.db" org-timeblock-db-directory))

(defun org-timeblock-db-open ()
  "Open a connection to the org-timeblock database.
Creates the directory if it does not exist."
  (let ((dir (expand-file-name org-timeblock-db-directory)))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (setq org-timeblock-db--connection
          (sqlite-open (org-timeblock-db--db-path)))
    (sqlite-execute org-timeblock-db--connection "PRAGMA foreign_keys = ON;")
    org-timeblock-db--connection))

(defun org-timeblock-db-close ()
  "Close the database connection."
  (when org-timeblock-db--connection
    (sqlite-close org-timeblock-db--connection)
    (setq org-timeblock-db--connection nil)))

(defun org-timeblock-db--ensure-connection ()
  "Ensure a database connection is open."
  (unless org-timeblock-db--connection
    (org-timeblock-db-open)))

(defun org-timeblock-db-setup ()
  "Initialize or migrate the database schema."
  (interactive)
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'")))
    (if rows
        (let ((current (caar (sqlite-select org-timeblock-db--connection
                                           "SELECT MAX(version) FROM schema_version"))))
          (cond
           ((and current (< current 2))
            ;; v1 -> v2: add color column to categories
            (sqlite-execute org-timeblock-db--connection
                            "ALTER TABLE categories ADD COLUMN color TEXT;")
            (sqlite-execute org-timeblock-db--connection
                            "INSERT INTO schema_version (version) VALUES (2);")
            ;; Backfill colors for existing categories
            (org-timeblock-db--backfill-colors)
            (message "org-timeblock-db: migrated v1 -> v2 (category colors)"))
           ((or (null current) (< current org-timeblock-db--schema-version))
            ;; Future migrations go here
            nil)
           (t
            (message "org-timeblock-db: schema is up to date (v%d)" org-timeblock-db--schema-version))))
      ;; No schema_version table: fresh install
      (dolist (stmt (org-timeblock-db--split-sql org-timeblock-db--schema-sql))
        (sqlite-execute org-timeblock-db--connection stmt))
      (message "org-timeblock-db: schema initialized (v%d)" org-timeblock-db--schema-version))))

(defun org-timeblock-db--split-sql (sql)
  "Split SQL string into individual statements, ignoring empty ones."
  (let ((stmts (split-string sql ";" t "[ \t\n]+")))
    (mapcar (lambda (s) (concat (string-trim s) ";")) stmts)))

;;; ---- Conversion helpers ----

(defun org-timeblock-db--row-to-work-log (row)
  "Convert a ROW from work_logs SELECT to a plist."
  (list :id (nth 0 row)
        :date (nth 1 row)
        :title (nth 2 row)
        :start-time (nth 3 row)
        :end-time (nth 4 row)
        :category-id (nth 5 row)
        :source (nth 6 row)))

(defun org-timeblock-db--row-to-category (row)
  "Convert a ROW from categories SELECT to a plist."
  (list :id (nth 0 row)
        :name (nth 1 row)
        :parent-id (nth 2 row)
        :color (nth 3 row)
        :created-at (nth 4 row)
        :updated-at (nth 5 row)))

(defun org-timeblock-db--row-to-attendance (row)
  "Convert a ROW from attendance SELECT to a plist."
  (list :date (nth 0 row)
        :clock-in (nth 1 row)
        :clock-out (nth 2 row)))

;;; ---- work_logs CRUD ----

(defun org-timeblock-db-insert-work-log (date title start-time end-time &optional category-id source)
  "Insert a work log entry and return the new row id.
DATE is \"YYYY-MM-DD\", START-TIME and END-TIME are \"HH:MM\".
SOURCE defaults to \"manual\"."
  (org-timeblock-db--ensure-connection)
  (let ((src (or source "manual")))
    (sqlite-execute org-timeblock-db--connection
                    "INSERT INTO work_logs (date, title, start_time, end_time, category_id, source)
                     VALUES (?, ?, ?, ?, ?, ?)"
                    (list date title start-time end-time category-id src))
    (caar (sqlite-select org-timeblock-db--connection "SELECT last_insert_rowid()"))))

(defun org-timeblock-db-update-work-log (id &rest attrs)
  "Update work log ID with ATTRS.
ATTRS is a plist with keys :title, :start-time, :end-time, :category-id, :source."
  (org-timeblock-db--ensure-connection)
  (let ((sets '())
        (vals '()))
    (when (plist-member attrs :title)
      (push "title = ?" sets)
      (push (plist-get attrs :title) vals))
    (when (plist-member attrs :start-time)
      (push "start_time = ?" sets)
      (push (plist-get attrs :start-time) vals))
    (when (plist-member attrs :end-time)
      (push "end_time = ?" sets)
      (push (plist-get attrs :end-time) vals))
    (when (plist-member attrs :category-id)
      (push "category_id = ?" sets)
      (push (plist-get attrs :category-id) vals))
    (when (plist-member attrs :source)
      (push "source = ?" sets)
      (push (plist-get attrs :source) vals))
    (when sets
      (push "updated_at = datetime('now','localtime')" sets)
      (let ((sql (format "UPDATE work_logs SET %s WHERE id = ?"
                         (string-join (nreverse sets) ", "))))
        (sqlite-execute org-timeblock-db--connection sql
                        (nconc (nreverse vals) (list id)))))))

(defun org-timeblock-db-delete-work-log (id)
  "Delete work log with ID."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "DELETE FROM work_logs WHERE id = ?" (list id)))

(defun org-timeblock-db-get-work-logs-by-date (date)
  "Return work logs for DATE as a list of plists.
Sorted by start_time."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT id, date, title, start_time, end_time, category_id, source
                              FROM work_logs WHERE date = ? ORDER BY start_time"
                             (list date))))
    (mapcar #'org-timeblock-db--row-to-work-log rows)))

(defun org-timeblock-db-check-collision (date start-time end-time &optional exclude-id)
  "Check if a work log would collide with existing entries on DATE.
Returns non-nil if a collision exists.
EXCLUDE-ID can be used to exclude a specific work log (for updates)."
  (org-timeblock-db--ensure-connection)
  (let* ((eid (or exclude-id -1))
         (rows (sqlite-select org-timeblock-db--connection
                              "SELECT COUNT(*) FROM work_logs
                               WHERE date = ? AND id != ? AND start_time < ? AND end_time > ?"
                              (list date eid end-time start-time))))
    (> (caar rows) 0)))

(defun org-timeblock-db-delete-work-logs-by-date (date)
  "Delete all work logs for DATE."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "DELETE FROM work_logs WHERE date = ?" (list date)))

(defun org-timeblock-db-delete-work-logs-before-date (date)
  "Delete all work logs before DATE."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "DELETE FROM work_logs WHERE date < ?" (list date)))

;;; ---- categories CRUD ----

(defun org-timeblock-db-insert-category (name &optional parent-id)
  "Insert a category with NAME and optional PARENT-ID. Return new id.
Color is automatically assigned based on parent palette or child derivation."
  (org-timeblock-db--ensure-connection)
  (let ((color (org-timeblock-db--auto-assign-color parent-id)))
    (sqlite-execute org-timeblock-db--connection
                    "INSERT INTO categories (name, parent_id, color) VALUES (?, ?, ?)"
                    (list name parent-id color))
    (caar (sqlite-select org-timeblock-db--connection "SELECT last_insert_rowid()"))))

(defun org-timeblock-db-update-category (id name)
  "Update category ID with new NAME."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "UPDATE categories SET name = ?, updated_at = datetime('now','localtime') WHERE id = ?"
                  (list name id)))

(defun org-timeblock-db-delete-category (id)
  "Delete category with ID."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "DELETE FROM categories WHERE id = ?" (list id)))

(defun org-timeblock-db-get-categories ()
  "Return all categories as a list of plists."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT id, name, parent_id, color, created_at, updated_at
                              FROM categories ORDER BY name")))
    (mapcar #'org-timeblock-db--row-to-category rows)))

(defun org-timeblock-db-get-child-categories (parent-id)
  "Return child categories of PARENT-ID as a list of plists."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT id, name, parent_id, color, created_at, updated_at
                              FROM categories WHERE parent_id = ? ORDER BY name"
                             (list parent-id))))
    (mapcar #'org-timeblock-db--row-to-category rows)))

;;; ---- title_category_map ----

(defun org-timeblock-db-upsert-title-category-map (title category-id)
  "Insert or update a title-to-category mapping."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "INSERT INTO title_category_map (title, category_id, updated_at)
                   VALUES (?, ?, datetime('now','localtime'))
                   ON CONFLICT(title) DO UPDATE SET
                     category_id = excluded.category_id,
                     updated_at = excluded.updated_at"
                  (list title category-id)))

(defun org-timeblock-db-get-known-titles ()
  "Return a list of all known titles from title_category_map and work_logs."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT DISTINCT title FROM (
                                SELECT title FROM title_category_map
                                UNION
                                SELECT title FROM work_logs
                              ) ORDER BY title")))
    (mapcar #'car rows)))

(defun org-timeblock-db-get-category-for-title (title)
  "Return the category-id mapped to TITLE, or nil."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT category_id FROM title_category_map WHERE title = ?"
                             (list title))))
    (when rows (caar rows))))

;;; ---- attendance ----

(defun org-timeblock-db-clock-in (date time)
  "Record clock-in for DATE at TIME (HH:MM).
Creates or updates the attendance record."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "INSERT INTO attendance (date, clock_in)
                   VALUES (?, ?)
                   ON CONFLICT(date) DO UPDATE SET
                     clock_in = excluded.clock_in,
                     updated_at = datetime('now','localtime')"
                  (list date time)))

(defun org-timeblock-db-clock-out (date time)
  "Record clock-out for DATE at TIME (HH:MM).
Creates or updates the attendance record."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "INSERT INTO attendance (date, clock_out)
                   VALUES (?, ?)
                   ON CONFLICT(date) DO UPDATE SET
                     clock_out = excluded.clock_out,
                     updated_at = datetime('now','localtime')"
                  (list date time)))

(defun org-timeblock-db-get-attendance (date)
  "Return attendance record for DATE as a plist, or nil."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT date, clock_in, clock_out FROM attendance WHERE date = ?"
                             (list date))))
    (when rows
      (org-timeblock-db--row-to-attendance (car rows)))))

(defun org-timeblock-db-get-attendance-dates ()
  "Return a list of all dates with attendance records."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT date FROM attendance ORDER BY date")))
    (mapcar #'car rows)))

(defun org-timeblock-db-get-next-attendance-date (date)
  "Return the next attendance date after DATE, or nil."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT date FROM attendance WHERE date > ? ORDER BY date LIMIT 1"
                             (list date))))
    (when rows (caar rows))))

(defun org-timeblock-db-get-prev-attendance-date (date)
  "Return the previous attendance date before DATE, or nil."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT date FROM attendance WHERE date < ? ORDER BY date DESC LIMIT 1"
                             (list date))))
    (when rows (caar rows))))

(defun org-timeblock-db-get-next-unconfirmed-date (date)
  "Return the next date after DATE that has attendance but no work logs, or nil."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT a.date FROM attendance a
                              LEFT JOIN work_logs w ON a.date = w.date
                              WHERE a.date > ? AND w.id IS NULL
                              ORDER BY a.date LIMIT 1"
                             (list date))))
    (when rows (caar rows))))

(defun org-timeblock-db-get-prev-unconfirmed-date (date)
  "Return the previous date before DATE that has attendance but no work logs, or nil."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT a.date FROM attendance a
                              LEFT JOIN work_logs w ON a.date = w.date
                              WHERE a.date < ? AND w.id IS NULL
                              ORDER BY a.date DESC LIMIT 1"
                             (list date))))
    (when rows (caar rows))))

;;; ---- default_break ----

(defun org-timeblock-db-get-default-break ()
  "Return the default break times as a plist (:start-time :end-time)."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT start_time, end_time FROM default_break WHERE id = 1")))
    (when rows
      (list :start-time (nth 0 (car rows))
            :end-time (nth 1 (car rows))))))

(defun org-timeblock-db-update-default-break (start-time end-time)
  "Update the default break to START-TIME and END-TIME."
  (org-timeblock-db--ensure-connection)
  (sqlite-execute org-timeblock-db--connection
                  "UPDATE default_break SET start_time = ?, end_time = ? WHERE id = 1"
                  (list start-time end-time)))

;;; ---- color utilities ----

(defconst org-timeblock-db--parent-palette
  '("#7287fd"   ; lavender (blue-violet)
    "#8839ef"   ; mauve (purple)
    "#ea76cb"   ; pink
    "#e78284"   ; red (softened)
    "#fe640b"   ; peach (orange)
    "#e5c890"   ; yellow (softened)
    "#a6d189"   ; green (softened)
    "#81c8be"   ; teal (softened)
    "#99d1db"   ; sapphire (cyan, softened)
    "#8caaee"   ; blue (softened)
    "#eebebe")  ; flamingo (softened)
  "11 parent category base colors. Rosewater is reserved for break.")

(defconst org-timeblock-db--break-color "#f2d5cf"
  "Dedicated color for break entries (rosewater).")

(defun org-timeblock-db--hex-to-hsl (hex)
  "Convert HEX color string like \"#rrggbb\" to (H S L) in 0.0-1.0 range."
  (let* ((r (/ (string-to-number (substring hex 1 3) 16) 255.0))
         (g (/ (string-to-number (substring hex 3 5) 16) 255.0))
         (b (/ (string-to-number (substring hex 5 7) 16) 255.0))
         (cmax (max r g b))
         (cmin (min r g b))
         (delta (- cmax cmin))
         (l (/ (+ cmax cmin) 2.0))
         (s (if (= delta 0.0) 0.0
              (/ delta (- 1.0 (abs (- (* 2.0 l) 1.0))))))
         (h (cond
             ((= delta 0.0) 0.0)
             ((= cmax r) (/ (mod (/ (- g b) delta) 6.0) 6.0))
             ((= cmax g) (/ (+ (/ (- b r) delta) 2.0) 6.0))
             (t           (/ (+ (/ (- r g) delta) 4.0) 6.0)))))
    (list (mod (+ h 1.0) 1.0) s l)))

(defun org-timeblock-db--hsl-to-hex (h s l)
  "Convert H S L (0.0-1.0) to hex color string \"#rrggbb\"."
  (let* ((c (* (- 1.0 (abs (- (* 2.0 l) 1.0))) s))
         (x (* c (- 1.0 (abs (- (mod (* h 6.0) 2.0) 1.0)))))
         (m (- l (/ c 2.0)))
         (h6 (* h 6.0))
         (rgb (cond
               ((< h6 1) (list c x 0.0))
               ((< h6 2) (list x c 0.0))
               ((< h6 3) (list 0.0 c x))
               ((< h6 4) (list 0.0 x c))
               ((< h6 5) (list x 0.0 c))
               (t         (list c 0.0 x)))))
    (format "#%02x%02x%02x"
            (round (* (+ (nth 0 rgb) m) 255))
            (round (* (+ (nth 1 rgb) m) 255))
            (round (* (+ (nth 2 rgb) m) 255)))))

(defun org-timeblock-db--child-color (parent-hex child-index)
  "Generate child color from PARENT-HEX at CHILD-INDEX (0-based, wraps mod 6).
Shifts hue by varying amounts and slightly adjusts saturation/lightness."
  (let* ((idx (mod child-index 6))
         (hsl (org-timeblock-db--hex-to-hsl parent-hex))
         (h (nth 0 hsl))
         (s (nth 1 hsl))
         (l (nth 2 hsl))
         ;; Hue shifts in degrees: +15, -15, +30, -30, +10, -10
         (hue-shifts '(0.042 -0.042 0.083 -0.083 0.028 -0.028))
         (new-h (mod (+ h (nth idx hue-shifts) 1.0) 1.0))
         ;; Slight saturation/lightness variation
         (sat-adj '(-0.03 0.03 -0.05 0.05 -0.02 0.02))
         (lit-adj '(0.02 -0.02 0.04 -0.04 0.01 -0.01))
         (new-s (max 0.0 (min 1.0 (+ s (nth idx sat-adj)))))
         (new-l (max 0.0 (min 1.0 (+ l (nth idx lit-adj))))))
    (org-timeblock-db--hsl-to-hex new-h new-s new-l)))

(defun org-timeblock-db--auto-assign-color (parent-id)
  "Return hex color string for a new category.
If PARENT-ID is nil, pick the first unused palette color.
If PARENT-ID is non-nil, pick the first unused child-derived color from parent.
When all colors are exhausted, wraps around to reuse."
  (org-timeblock-db--ensure-connection)
  (if parent-id
      ;; Child category: derive from parent color, skip used ones
      (let* ((parent-rows (sqlite-select org-timeblock-db--connection
                                         "SELECT color FROM categories WHERE id = ?"
                                         (list parent-id)))
             (parent-color (and parent-rows (caar parent-rows)))
             (sibling-colors (mapcar #'car
                                     (sqlite-select org-timeblock-db--connection
                                                    "SELECT color FROM categories WHERE parent_id = ?"
                                                    (list parent-id))))
             (used (make-hash-table :test 'equal)))
        (dolist (c sibling-colors) (when c (puthash c t used)))
        (if parent-color
            (let ((found nil) (i 0))
              (while (and (not found) (< i 6))
                (let ((candidate (org-timeblock-db--child-color parent-color i)))
                  (unless (gethash candidate used)
                    (setq found candidate)))
                (setq i (1+ i)))
              ;; All 6 exhausted: wrap around with index = sibling count
              (or found (org-timeblock-db--child-color parent-color (length sibling-colors))))
          (car org-timeblock-db--parent-palette)))
    ;; Parent category: pick first unused palette color
    (let* ((used-colors (mapcar #'car
                                (sqlite-select org-timeblock-db--connection
                                               "SELECT color FROM categories WHERE parent_id IS NULL")))
           (used (make-hash-table :test 'equal))
           (palette org-timeblock-db--parent-palette)
           (found nil))
      (dolist (c used-colors) (when c (puthash c t used)))
      (dolist (color palette)
        (unless (or found (gethash color used))
          (setq found color)))
      ;; All palette colors used: wrap with mod
      (or found (nth (mod (length used-colors) (length palette)) palette)))))

(defun org-timeblock-db-get-category-color-map ()
  "Return alist of (category-id . hex-color) for all categories."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT id, color FROM categories WHERE color IS NOT NULL")))
    (mapcar (lambda (row) (cons (nth 0 row) (nth 1 row))) rows)))

(defun org-timeblock-db--backfill-colors ()
  "Assign colors to existing categories that have no color set.
Processes parent categories first, then children."
  (org-timeblock-db--ensure-connection)
  ;; Parents first
  (let ((parents (sqlite-select org-timeblock-db--connection
                                "SELECT id FROM categories WHERE parent_id IS NULL AND color IS NULL ORDER BY id")))
    (dolist (row parents)
      (let ((color (org-timeblock-db--auto-assign-color nil)))
        (sqlite-execute org-timeblock-db--connection
                        "UPDATE categories SET color = ? WHERE id = ?"
                        (list color (car row))))))
  ;; Children next
  (let ((children (sqlite-select org-timeblock-db--connection
                                 "SELECT id, parent_id FROM categories WHERE parent_id IS NOT NULL AND color IS NULL ORDER BY id")))
    (dolist (row children)
      (let ((color (org-timeblock-db--auto-assign-color (nth 1 row))))
        (sqlite-execute org-timeblock-db--connection
                        "UPDATE categories SET color = ? WHERE id = ?"
                        (list color (car row)))))))

;;; ---- summary ----

(defun org-timeblock-db-get-category-summary-by-date (date)
  "Return category summary for DATE as a list of (:category-name :total-minutes).
Entries without a category are grouped under \"(uncategorized)\"."
  (org-timeblock-db--ensure-connection)
  (let ((rows (sqlite-select org-timeblock-db--connection
                             "SELECT COALESCE(c.name, '(uncategorized)') AS cat_name,
                                     SUM(
                                       (CAST(substr(w.end_time, 1, 2) AS INTEGER) * 60
                                        + CAST(substr(w.end_time, 4, 2) AS INTEGER))
                                       - (CAST(substr(w.start_time, 1, 2) AS INTEGER) * 60
                                          + CAST(substr(w.start_time, 4, 2) AS INTEGER))
                                     ) AS total_minutes
                              FROM work_logs w
                              LEFT JOIN categories c ON w.category_id = c.id
                              WHERE w.date = ?
                              GROUP BY cat_name
                              ORDER BY total_minutes DESC"
                             (list date))))
    (mapcar (lambda (row)
              (list :category-name (nth 0 row)
                    :total-minutes (nth 1 row)))
            rows)))

(provide 'org-timeblock-db)

;;; org-timeblock-db.el ends here
