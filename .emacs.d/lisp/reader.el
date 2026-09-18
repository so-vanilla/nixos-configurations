;;; reader.el --- Remote PDF/EPUB reader for sub-frame -*- lexical-binding: t; -*-

;;; Commentary:
;; Provides a sub-frame based PDF/EPUB reader controlled from the main frame.
;; PDF support requires pdf-tools, EPUB support requires nov.el.

;;; Code:

(require 'cl-lib)
(require 'seq)

(declare-function pdf-view-goto-page "pdf-view" (page &optional window))
(declare-function pdf-view-current-page "pdf-view" (&optional window))
(declare-function pdf-view-next-page-command "pdf-view" (&optional n))
(declare-function pdf-view-previous-page-command "pdf-view" (&optional n))
(declare-function pdf-view-scroll-up-or-next-page "pdf-view" (&optional arg))
(declare-function pdf-view-scroll-down-or-previous-page "pdf-view" (&optional arg))
(declare-function pdf-view-enlarge "pdf-view" (factor))
(declare-function pdf-view-shrink "pdf-view" (factor))
(declare-function pdf-view-fit-width-to-window "pdf-view" ())
(declare-function pdf-view-fit-page-to-window "pdf-view" ())
(declare-function pdf-cache-number-of-pages "pdf-cache" ())
(declare-function nov-next-document "nov" ())
(declare-function nov-previous-document "nov" ())
(declare-function nov-goto-toc "nov" ())

(defgroup reader nil
  "Remote PDF/EPUB reader for sub-frame."
  :group 'multimedia
  :prefix "reader-")

(defcustom reader-frame-parameters '((width . 90) (height . 50))
  "Additional frame parameters for the reader sub-frame."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'reader)

(defcustom reader-pdf-default-fit 'fit-page
  "Default fit mode for PDF display."
  :type '(choice (const :tag "Fit page" fit-page)
                 (const :tag "Fit width" fit-width))
  :group 'reader)

(defcustom reader-pdf-dual-page nil
  "When non-nil, display two pages side by side."
  :type 'boolean
  :group 'reader)

(defcustom reader-pdf-right-to-left nil
  "When non-nil, use right-to-left page ordering."
  :type 'boolean
  :group 'reader)

(defcustom reader-pdf-dual-odd-left t
  "When non-nil, odd-numbered pages appear on the left in dual-page mode."
  :type 'boolean
  :group 'reader)

(defvar reader--frame nil
  "The reader sub-frame.")

(defvar reader--dual-page-p nil
  "Non-nil when dual-page mode is active.")

(defvar reader--secondary-buffer nil
  "Indirect buffer for the second page in dual-page mode.")

;;; Internal functions

(defun reader--find-frame ()
  "Return the reader frame if it exists and is alive."
  (when (and reader--frame (frame-live-p reader--frame))
    reader--frame))

(defun reader--ensure-frame ()
  "Return the reader frame or signal an error."
  (or (reader--find-frame)
      (user-error "Reader frame is not open")))

(defun reader--current-buffer-type ()
  "Return the type of the current buffer: `pdf', `epub', or nil."
  (cond
   ((derived-mode-p 'pdf-view-mode) 'pdf)
   ((derived-mode-p 'nov-mode) 'epub)))

(defun reader--buffer-type ()
  "Return the buffer type in the reader frame."
  (when-let ((frame (reader--find-frame)))
    (with-selected-frame frame
      (reader--current-buffer-type))))

(defun reader--execute-in-frame (fn &rest args)
  "Execute FN with ARGS in the reader frame's selected window."
  (let ((frame (reader--ensure-frame)))
    (with-selected-frame frame
      (with-selected-window (frame-selected-window frame)
        (apply fn args)))))

(defun reader--dispatch (pdf-fn epub-fn &rest args)
  "Dispatch to PDF-FN or EPUB-FN in the reader frame."
  (reader--execute-in-frame
   (lambda ()
     (pcase (reader--current-buffer-type)
       ('pdf (apply pdf-fn args))
       ('epub (apply epub-fn args))
       (_ (user-error "No PDF or EPUB buffer in reader frame"))))))

(defun reader--on-frame-deleted (frame)
  "Clean up when the reader FRAME is deleted."
  (when (and reader--frame (eq frame reader--frame))
    (reader--dual-page-teardown)
    (setq reader--frame nil)
    (reader-mode -1)))

;;; Dual-page functions

(defun reader--page-pair (current-page total-pages)
  "Calculate the page pair for CURRENT-PAGE given TOTAL-PAGES.
Returns (LEFT-PAGE . RIGHT-PAGE).  Either may be nil if out of range."
  (let* ((first-page
          (if reader-pdf-dual-odd-left
              ;; Odd pages start spreads: (1,2), (3,4), (5,6)...
              (if (cl-oddp current-page) current-page (1- current-page))
            ;; Even pages start spreads: 1 alone, (2,3), (4,5)...
            (if (= current-page 1) 1
              (if (cl-evenp current-page) current-page (1- current-page)))))
         (second-page
          (cond
           ((and (not reader-pdf-dual-odd-left) (= first-page 1)) nil)
           ((<= (1+ first-page) total-pages) (1+ first-page))
           (t nil))))
    (if reader-pdf-right-to-left
        (cons second-page first-page)
      (cons first-page second-page))))

(defun reader--dual-page-setup ()
  "Set up dual-page display in the reader frame."
  (let* ((frame (reader--ensure-frame))
         (win (frame-selected-window frame))
         (buf (window-buffer win))
         (current-page (pdf-view-current-page win))
         (total-pages (pdf-cache-number-of-pages))
         (pair (reader--page-pair current-page total-pages))
         (indirect (make-indirect-buffer buf
                     (generate-new-buffer-name
                      (concat (buffer-name buf) "<2>"))
                     t)))
    (setq reader--secondary-buffer indirect)
    (setq reader--dual-page-p t)
    (delete-other-windows win)
    (let ((right-win (split-window win nil t)))
      (when (car pair)
        (with-selected-window win
          (pdf-view-goto-page (car pair))))
      (set-window-buffer right-win indirect)
      (when (cdr pair)
        (with-selected-window right-win
          (pdf-view-goto-page (cdr pair)))))))

(defun reader--dual-page-teardown ()
  "Tear down dual-page display."
  (when reader--dual-page-p
    (setq reader--dual-page-p nil)
    (when (and reader--secondary-buffer (buffer-live-p reader--secondary-buffer))
      (kill-buffer reader--secondary-buffer))
    (setq reader--secondary-buffer nil)
    (when-let ((frame (reader--find-frame)))
      (with-selected-frame frame
        (delete-other-windows)))))

(defun reader--dual-page-sync ()
  "Synchronize dual-page display after page change.
Must be called within the reader frame context."
  (when reader--dual-page-p
    (let* ((current-page (pdf-view-current-page))
           (total (pdf-cache-number-of-pages))
           (pair (reader--page-pair current-page total))
           (left-page (or (car pair) (cdr pair)))
           (right-page (or (cdr pair) (car pair))))
      (when left-page
        (pdf-view-goto-page left-page))
      (when-let ((sec-win (seq-find
                           (lambda (w)
                             (and reader--secondary-buffer
                                  (buffer-live-p reader--secondary-buffer)
                                  (eq (window-buffer w) reader--secondary-buffer)))
                           (window-list))))
        (when right-page
          (with-selected-window sec-win
            (pdf-view-goto-page right-page)))))))

;;; Public API

;;;###autoload
(defun reader-open (file)
  "Open FILE in the reader sub-frame."
  (interactive "fOpen file: ")
  (when (reader--find-frame)
    (reader-close))
  (let* ((params (append '((reader . t)) reader-frame-parameters))
         (frame (make-frame params)))
    (setq reader--frame frame)
    (with-selected-frame frame
      (find-file file)
      (when (derived-mode-p 'pdf-view-mode)
        (pcase reader-pdf-default-fit
          ('fit-page (pdf-view-fit-page-to-window))
          ('fit-width (pdf-view-fit-width-to-window)))
        (when reader-pdf-dual-page
          (reader--dual-page-setup))))
    (reader-mode 1)))

(defun reader-close ()
  "Close the reader sub-frame."
  (interactive)
  (when-let ((frame (reader--find-frame)))
    (reader--dual-page-teardown)
    (setq reader--frame nil)
    (delete-frame frame)
    (reader-mode -1)))

(defun reader-next-page ()
  "Go to the next page in the reader frame.
In dual-page mode, advances by 2 pages."
  (interactive)
  (reader--execute-in-frame
   (lambda ()
     (pcase (reader--current-buffer-type)
       ('pdf
        (if reader--dual-page-p
            (let* ((current (pdf-view-current-page))
                   (total (pdf-cache-number-of-pages))
                   (pair (reader--page-pair current total))
                   (step (if (and (car pair) (cdr pair)) 2 1))
                   (next (min (+ current step) total)))
              (pdf-view-goto-page next)
              (reader--dual-page-sync))
          (pdf-view-next-page-command 1)))
       ('epub (nov-next-document))
       (_ (user-error "No PDF or EPUB buffer in reader frame"))))))

(defun reader-previous-page ()
  "Go to the previous page in the reader frame.
In dual-page mode, goes back by 2 pages."
  (interactive)
  (reader--execute-in-frame
   (lambda ()
     (pcase (reader--current-buffer-type)
       ('pdf
        (if reader--dual-page-p
            (let* ((current (pdf-view-current-page))
                   (total (pdf-cache-number-of-pages))
                   (pair (reader--page-pair current total))
                   (step (if (and (car pair) (cdr pair)) 2 1))
                   (prev (max (- current step) 1)))
              (pdf-view-goto-page prev)
              (reader--dual-page-sync))
          (pdf-view-previous-page-command 1)))
       ('epub (nov-previous-document))
       (_ (user-error "No PDF or EPUB buffer in reader frame"))))))

(defun reader-scroll-up ()
  "Scroll up in the reader frame."
  (interactive)
  (reader--dispatch
   #'pdf-view-scroll-up-or-next-page
   #'scroll-up-command))

(defun reader-scroll-down ()
  "Scroll down in the reader frame."
  (interactive)
  (reader--dispatch
   #'pdf-view-scroll-down-or-previous-page
   #'scroll-down-command))

(defun reader-goto-page (n)
  "Go to page N in the reader frame.
For EPUB, shows the table of contents."
  (interactive "nPage: ")
  (reader--execute-in-frame
   (lambda ()
     (pcase (reader--current-buffer-type)
       ('pdf
        (pdf-view-goto-page n)
        (when reader--dual-page-p
          (reader--dual-page-sync)))
       ('epub (nov-goto-toc))
       (_ (user-error "No PDF or EPUB buffer in reader frame"))))))

(defun reader-zoom-in ()
  "Zoom in on the reader frame."
  (interactive)
  (reader--dispatch
   (lambda () (pdf-view-enlarge 1.25))
   #'text-scale-increase))

(defun reader-zoom-out ()
  "Zoom out on the reader frame."
  (interactive)
  (reader--dispatch
   (lambda () (pdf-view-shrink 1.25))
   #'text-scale-decrease))

(defun reader-fit-width ()
  "Fit to width in the reader frame (PDF only)."
  (interactive)
  (reader--execute-in-frame
   (lambda ()
     (unless (eq (reader--current-buffer-type) 'pdf)
       (user-error "Fit-width is only available for PDF"))
     (pdf-view-fit-width-to-window))))

(defun reader-fit-page ()
  "Fit entire page in the reader frame (PDF only)."
  (interactive)
  (reader--execute-in-frame
   (lambda ()
     (unless (eq (reader--current-buffer-type) 'pdf)
       (user-error "Fit-page is only available for PDF"))
     (pdf-view-fit-page-to-window))))

(defun reader-toggle-dual-page ()
  "Toggle dual-page mode (PDF only)."
  (interactive)
  (reader--execute-in-frame
   (lambda ()
     (unless (eq (reader--current-buffer-type) 'pdf)
       (user-error "Dual-page is only available for PDF"))
     (if reader--dual-page-p
         (reader--dual-page-teardown)
       (reader--dual-page-setup))
     (message "Dual-page: %s" (if reader--dual-page-p "ON" "OFF")))))

(defun reader-toggle-direction ()
  "Toggle LTR/RTL direction."
  (interactive)
  (setq reader-pdf-right-to-left (not reader-pdf-right-to-left))
  (when reader--dual-page-p
    (reader--execute-in-frame #'reader--dual-page-sync))
  (message "Direction: %s" (if reader-pdf-right-to-left "RTL" "LTR")))

(defun reader-toggle-odd-even ()
  "Toggle odd/even page placement in dual-page mode."
  (interactive)
  (setq reader-pdf-dual-odd-left (not reader-pdf-dual-odd-left))
  (when reader--dual-page-p
    (reader--execute-in-frame #'reader--dual-page-sync))
  (message "Odd pages on %s" (if reader-pdf-dual-odd-left "left" "right")))

;;; Minor mode

(defvar reader-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-M-<next>") #'reader-next-page)
    (define-key map (kbd "C-M-<prior>") #'reader-previous-page)
    map)
  "Keymap for `reader-mode'.")

;;;###autoload
(define-minor-mode reader-mode
  "Global minor mode for controlling the reader sub-frame."
  :global t
  :lighter " Reader"
  :keymap reader-mode-map
  (if reader-mode
      (add-hook 'delete-frame-functions #'reader--on-frame-deleted)
    (remove-hook 'delete-frame-functions #'reader--on-frame-deleted)))

(provide 'reader)

;;; reader.el ends here
