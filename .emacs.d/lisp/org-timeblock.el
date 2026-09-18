;;; org-timeblock.el --- Time block sidebar and work log management -*- lexical-binding: t; -*-

(require 'org-timeblock-db)
(require 'org-timeblock-display)
(require 'org-timeblock-worklog)
(require 'org-timeblock-category)

(defgroup org-timeblock nil
  "Time block sidebar and work log management."
  :group 'org
  :prefix "org-timeblock-")

;;;###autoload
(defun org-timeblock-setup ()
  "Initialize the org-timeblock database."
  (interactive)
  (org-timeblock-db-setup))

;;;###autoload
(defun org-timeblock-show ()
  "Show the org-timeblock sidebar.  Initialize DB if needed."
  (interactive)
  (unless org-timeblock-db--connection
    (org-timeblock-setup))
  (org-timeblock-display-show))

;;;###autoload
(defun org-timeblock-toggle ()
  "Toggle the org-timeblock sidebar."
  (interactive)
  (unless org-timeblock-db--connection
    (org-timeblock-setup))
  (org-timeblock-display-toggle))

;;;###autoload
(defun org-timeblock-close ()
  "Close the org-timeblock sidebar."
  (interactive)
  (org-timeblock-display-close))

(provide 'org-timeblock)
;;; org-timeblock.el ends here
