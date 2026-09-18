;;; ade-public-test.el --- ADE public command tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Isolated tests for the explicit user-facing composition commands.  All
;; transports, processes, completion readers, and UI effects are stubbed.

;;; Code:

(require 'ert)
(require 'json)
(add-to-list 'load-path
             (expand-file-name "../.emacs.d/lisp/ade"
                               (file-name-directory (or load-file-name
                                                        buffer-file-name))))
(require 'ade)

(defun ade-public-test--records ()
  "Register and return one current Workspace and selected idle Agent."
  (let* ((workspace
          (ade-workspace-create
           :uuid "public-workspace"
           :name "public"
           :root (file-name-as-directory (expand-file-name default-directory))
           :worktree nil
           :perspective-name "public-workspace"
           :prompt-buffer nil
           :agent-ids nil
           :selected-agent-id nil
           :metadata nil))
         (connection (ade-app-server-create))
         (agent
          (ade-agent-new
           :id "public-agent"
           :workspace-uuid "public-workspace"
           :thread-id "public-thread"
           :state 'idle)))
    (setf (ade-app-server-transport-open-p connection) t
          (ade-app-server-handshake-p connection) t
          (ade-agent-connection agent) connection
          (ade-agent-turn-origin agent) 'ade)
    (ade-core-register-workspace workspace)
    (ade-core-register-agent agent t)
    (list workspace agent)))

(defmacro ade-public-test--clean (&rest body)
  "Run BODY with a clean ADE registry and no live owned runtime."
  `(progn
     (ade-runtime-stop)
     (setq ade-runtime--current nil)
     (ade-core-reset)
     (unwind-protect (progn ,@body)
       (ade-runtime-stop)
       (setq ade-runtime--current nil)
       (ade-core-reset))))

(ert-deftest ade-public-require-does-not-start-owned-runtime ()
  (ade-public-test--clean
   (should (featurep 'ade))
   (should-not (ade-runtime-current))))

(ert-deftest ade-public-start-agent-is-explicit-and-non-displaying ()
  (ade-public-test--clean
   (let* ((records (ade-public-test--records))
          (agent (cadr records))
          (captured nil))
     (cl-letf (((symbol-function 'ade-runtime-start-agent)
                (lambda (&rest options)
                  (setq captured options)
                  agent))
               ((symbol-function 'pop-to-buffer)
                (lambda (&rest _args) (ert-fail "unexpected display"))))
       (should (eq (ade-start-agent) agent)))
     (should (functionp (plist-get captured :callback)))
     (should (functionp (plist-get captured :errorback))))))

(ert-deftest ade-public-model-selection-uses-discovered-model-and-effort ()
  (ade-public-test--clean
   (let* ((records (ade-public-test--records))
          (agent (cadr records))
          (model '((id . "luna")
                   (model . "gpt-luna")
                   (displayName . "Luna")
                   (supportedReasoningEfforts
                    . (((reasoningEffort . "high"))
                       ((reasoningEffort . "max"))))))
          (reads 0)
          (updated nil))
     (cl-letf (((symbol-function 'ade-model-list)
                (lambda (connection callback &rest _args)
                  (funcall callback (list model) connection)))
               ((symbol-function 'completing-read)
                (lambda (_prompt collection &rest _args)
                  (setq reads (1+ reads))
                  (if (= reads 1) (cadr collection) "max")))
               ((symbol-function 'ade-model-update)
                (lambda (sent-agent sent-model effort &rest _callbacks)
                  (setq updated (list sent-agent sent-model effort)))))
       (ade-select-model))
     (should (equal updated (list agent "gpt-luna" "max"))))))

(ert-deftest ade-public-approval-answer-is-selected-agent-only ()
  (ade-public-test--clean
   (let* ((records (ade-public-test--records))
          (agent (cadr records))
          (request
           (ade-request--make
            :id 7 :agent-id (ade-agent-id agent)
            :connection (ade-agent-connection agent)
            :thread-id (ade-agent-thread-id agent)
            :kind 'approval
            :method "item/commandExecution/requestApproval"
            :params nil
            :choices (list (list :value "accept" :label "Accept")
                           (list :value "cancel" :label "Cancel"))
            :status 'pending))
          (response nil))
     (cl-letf (((symbol-function 'ade-request-pending-for-agent)
                (lambda (selected)
                  (should (eq selected agent))
                  (list request)))
               ((symbol-function 'completing-read)
                (lambda (_prompt collection &rest _args) (car collection)))
               ((symbol-function 'ade-request-respond)
                (lambda (selected result &rest _callbacks)
                  (setq response (list selected result)))))
       (ade-answer-request))
     (should (eq (car response) request))
     (should (equal (cadr response) '((decision . "accept")))))))

(ert-deftest ade-public-tool-user-input-builds-protocol-shaped-object ()
  (ade-public-test--clean
   (let* ((request
           (ade-request--make
            :id 8 :agent-id "public-agent" :kind 'user-input
            :method "item/tool/requestUserInput"
            :params '((questions
                       ((id . "answer_id")
                        (question . "Choose")
                        (options ((label . "Yes")) ((label . "No"))))))
            :status 'pending))
          (response nil))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (&rest _args) "Yes")))
       (setq response (ade--read-request-response request)))
     (should
      (equal (json-serialize response)
             "{\"answers\":{\"answer_id\":{\"answers\":[\"Yes\"]}}}")))))

(provide 'ade-public-test)

;;; ade-public-test.el ends here
