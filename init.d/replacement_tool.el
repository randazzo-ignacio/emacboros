;; -*- lexical-binding: t; -*-

(defun ouroboros-replace-in-file (path search-text replace-text)
  "Find SEARCH-TEXT in PATH and replace it with REPLACE-TEXT.
SEARCH-TEXT is matched exactly as provided -- whitespace is significant."
  (condition-case err
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (if (search-forward search-text nil t)
            (progn
              ;; Move point to start of match before replacing
              (replace-match replace-text t t)
              ;; Atomic write: write to temp file, then rename
              (let ((tmp-file (concat path ".tmp")))
                (write-region (point-min) (point-max) tmp-file nil 'silent)
                (rename-file tmp-file path t))
              (format "SUCCESS: Replaced text in %s" path))
          (format "ERROR: Target string not found in %s" path)))
    (error (format "Error: Could not modify file '%s'. Reason: %s"
                   path (error-message-string err)))))

(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "replace_in_file"
  :description "Surgically replace a specific block of text in an existing file."
  :args (list '(:name "path" :type "string")
              '(:name "search_text" :type "string")
              '(:name "replace_text" :type "string"))
  :function #'ouroboros-replace-in-file))