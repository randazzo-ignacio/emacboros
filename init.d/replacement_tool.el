;; -*- lexical-binding: t; -*-

(defun ouroboros-replace-in-file (path search-text replace-text)
  "Find SEARCH-TEXT in PATH and replace it with REPLACE-TEXT."
  (condition-case err
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (let ((clean-search (string-trim search-text)))
          (if (search-forward clean-search nil t)
              (progn
                (replace-match replace-text t t)
                (write-region (point-min) (point-max) path)
                (message "SUCCESS: Replaced text in %s" path))
            (message "ERROR: Target string not found."))))
    (error (format "ERROR modifying file: %s" err))))

(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "replace_in_file"
  :description "Surgically replace a specific block of text in an existing file."
  :args (list '(:name "path" :type "string")
              '(:name "search_text" :type "string")
              '(:name "replace_text" :type "string"))
  :function #'ouroboros-replace-in-file))
