;; -*- lexical-binding: t; -*-

;; Native Directory Lister tool definition for gptel
(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "list_directory"
  :description "List the contents of a local directory. Use this to find files on the machine running Emacs."
  :args (list '(:name "path" :type "string" :description "Absolute path to the directory."))
  :function (lambda (path)
              (condition-case nil
                  (mapconcat #'identity (directory-files (expand-file-name path) nil "^[^.]") "\n")
                (error (format "Error: Directory '%s' not found or permission denied." path))))))

;; Native File Reader tool definition for gptel
(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "read_file"
  :description "Read the text contents of a local file into context."
  :args (list '(:name "filepath" :type "string" :description "Absolute path to the file."))
  :function (lambda (filepath)
              (condition-case nil
                  (with-temp-buffer
                    (insert-file-contents filepath)
                    (buffer-string))
                (error (format "Error: File '%s' not found or cannot be read." filepath))))))

;; Native File Writer tool definition for gptel
(add-to-list 'gptel-tools
             (gptel-make-tool
              :name "write_file"
              :description "Create a new file or completely overwrite an existing file with new text content. Use this to save new agent profiles or rewrite configurations."
              :args (list '(:name "filepath" :type "string" :description "Absolute path to the destination file.")
                          '(:name "content" :type "string" :description "The full text content to write into the file."))
              :function (lambda (filepath content)
                          (let* ((expanded-path (expand-file-name filepath))
                                 (buf (get-file-buffer expanded-path)))
                            (condition-case err
                                (progn
                                  (make-directory (file-name-directory expanded-path) t)
                                  (if buf
                                      ;; BUGFIX: If file is open in Emacs, write to the active buffer and save it.
                                      ;; This completely bypasses file-lock errors and "changed on disk" desyncs.
                                      (with-current-buffer buf
                                        (erase-buffer)
                                        (insert content)
                                        (save-buffer))
                                    ;; Otherwise, file is closed, safe to write directly to the hard drive
                                    (with-temp-file expanded-path
                                      (insert content)))
                                  (format "Success: File written to '%s'" expanded-path))
                              ;; BUGFIX: Bind the error to 'err' and expose the exact reason to the LLM
                              (error (format "Error: Failed to write file to '%s'. Emacs says: %s" 
                                             expanded-path (error-message-string err))))))))

;; Native File Appender tool definition for gptel
(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "append_file"
  :description "Append text content to the end of an existing file. Use this to add new notes, logs, or subheadings to a file without erasing its current contents. Automatically prepends a newline if the file does not already end with one, ensuring appended content always starts on a fresh line."
  :args (list '(:name "filepath" :type "string" :description "Absolute path to the file.")
              '(:name "content" :type "string" :description "The text content to add to the end of the file."))
  :function (lambda (filepath content)
              (condition-case err
                  (let* ((expanded-path (expand-file-name filepath))
                         (prefix
                          (if (and (file-exists-p expanded-path)
                                   (> (file-attribute-size (file-attributes expanded-path)) 0))
                              (with-temp-buffer
                                (insert-file-contents expanded-path)
                                (if (string-suffix-p "\n" (buffer-string))
                                    ""
                                  "\n"))
                            "")))
                    (write-region (concat prefix content) nil expanded-path t)
                    (format "Success: Content appended to '%s'" expanded-path))
                (error (format "Error: Failed to append to '%s'. Emacs says: %s"
                               filepath (error-message-string err))))))
