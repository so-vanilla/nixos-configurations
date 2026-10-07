;;; ade-model.el --- App Server model discovery and settings -*- lexical-binding: t; -*-

;;; Commentary:

;; Model names are discovered from App Server `model/list'; ADE never
;; hard-codes a model choice.  Settings changes are explicit and future-turn
;; scoped through `thread/settings/update'.  The corresponding updated event
;; remains the authoritative Agent/TUI reflection signal.

;;; Code:

(require 'cl-lib)
(require 'ade-app-server)
(require 'ade-agent)

(defgroup ade-model nil
  "Codex model discovery and settings for ADE."
  :group 'ade)

(defcustom ade-model-cache-ttl 300
  "Seconds for which a successful model/list cache remains fresh."
  :type 'number
  :group 'ade-model)

(defvar ade-model--cache nil
  "Cached `model/list' result as a plist.")

(defun ade-model-reset-cache ()
  "Clear the process-local model cache."
  (setq ade-model--cache nil)
  t)

(defun ade-model--json-get (object key)
  "Return KEY from an alist or plist OBJECT."
  (let* ((name (cond
                ((keywordp key) (substring (symbol-name key) 1))
                ((symbolp key) (symbol-name key))
                (t key)))
         (symbol (and (stringp name) (intern name)))
         (keyword (and (stringp name) (intern (concat ":" name)))))
    (and (listp object)
         (or (alist-get symbol object nil nil #'equal)
             (alist-get name object nil nil #'equal)
             (plist-get object keyword)
             (plist-get object symbol)))))

(defun ade-model-cached (&optional include-hidden)
  "Return cached model data, or nil when absent/expired.

When INCLUDE-HIDDEN is nil, hidden entries are removed from the returned
list.  The raw cache remains intact for a later explicit request."
  (when (and ade-model--cache
             (< (- (float-time) (plist-get ade-model--cache :fetched-at))
                ade-model-cache-ttl))
    (let ((data (plist-get ade-model--cache :data)))
      (if include-hidden
          data
        (cl-remove-if (lambda (model)
                        (ade-model--json-get model 'hidden))
                      data)))))

(defun ade-model-find (model-id &optional include-hidden)
  "Find MODEL-ID in the cached model list."
  (cl-find-if
   (lambda (model)
     (and (equal model-id (or (ade-model--json-get model 'id)
                              (ade-model--json-get model 'model)))
          (or include-hidden
              (not (ade-model--json-get model 'hidden)))))
   (ade-model-cached include-hidden)))

(defun ade-model-list
    (connection &optional callback errorback refresh include-hidden)
  "Discover models on CONNECTION and update the local cache.

When REFRESH is nil, a fresh cache is returned asynchronously to CALLBACK
without making a request.  CALLBACK receives the model data and connection;
ERRORBACK receives an error and connection."
  (let ((cached (and (not refresh) (ade-model-cached include-hidden))))
    (if cached
        (progn
          (when callback (funcall callback cached connection))
          cached)
      (ade-app-server-call
       connection "model/list"
       (list (cons 'includeHidden (and include-hidden t))
             (cons 'limit 200))
       (lambda (result)
         (let ((data (or (ade-model--json-get result 'data) '())))
           (setq ade-model--cache
                 (list :data data :fetched-at (float-time)
                       :next-cursor (ade-model--json-get result 'nextCursor)))
           (when callback
             (funcall callback
                      (if include-hidden data
                        (cl-remove-if
                         (lambda (model) (ade-model--json-get model 'hidden))
                         data))
                      connection))))
       (lambda (error)
         (when errorback (funcall errorback error connection)))))))

(defalias 'ade-model-refresh #'ade-model-list)

(defun ade-model-update (agent model &optional effort callback errorback)
  "Set AGENT's future-turn MODEL and optional EFFORT explicitly."
  (let ((connection (ade-agent-connection agent)))
    (unless (and connection (ade-app-server-connected-p connection))
      (signal 'ade-agent-not-ready-error (list "Agent is not connected")))
    (let ((params (list (cons 'threadId (ade-agent-thread-id agent))
                        (cons 'model model))))
      (when effort (setq params (append params (list (cons 'effort effort)))))
      (ade-app-server-call
       connection "thread/settings/update" params
       (lambda (result)
         ;; The updated event is authoritative, but reflecting the requested
         ;; values immediately keeps the local record useful before it arrives.
         (setf (ade-agent-model agent) model)
         (when effort (setf (ade-agent-effort agent) effort))
         (when callback (funcall callback result agent)))
       (lambda (error)
         (when errorback (funcall errorback error agent)))))))

(defalias 'ade-model-set #'ade-model-update)

(provide 'ade-model)

;;; ade-model.el ends here
