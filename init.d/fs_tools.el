;; -*- lexical-binding: t; -*-

;;; Native Filesystem Tools for gptel
;; Provides list_directory, read_file, write_file, append_file tools.
;;
;; Functions are extracted as named defuns (not inline lambdas) so they
;; can be unit-tested directly via ERT.

;;; --- list_directory ---

(defun my-gptel--fs-list-directory (path)
  "List the contents of directory PATH.
Returns newline-separated file names (excluding dotfiles).
On error, returns a string starting with 'Error:'."
  (condition-case nil
      (mapconcat #'identity
                 (directory-files (expand-file-name path) nil "^[^.]")
                 "\n")
    (error (format "Error: Directory '%s' not found or permission denied." path))))

(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "list_directory"
  :description "List the contents of a local directory. Use this to find files on the machine running Emacs."
  :args (list '(:name "path" :type "string" :description "Absolute path to the directory."))
  :function #'my-gptel--fs-list-directory))

;;; --- read_file ---

(defun my-gptel--fs-read-file (filepath)
  "Read the text contents of FILEPATH into a string.
On error, returns a string starting with 'Error:'."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents filepath)
        (buffer-string))
    (error (format "Error: File '%s' not found or cannot be read." filepath))))

(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "read_file"
  :description "Read the text contents of a local file into context."
  :args (list '(:name "filepath" :type "string" :description "Absolute path to the file."))
  :function #'my-gptel--fs-read-file))

;;; --- write_file ---

(defun my-gptel--fs-write-file (filepath content)
  "Write CONTENT to FILEPATH, creating parent dirs if needed.
If the file is open in an Emacs buffer, writes to that buffer and saves.
Otherwise, uses atomic write (temp file + rename).
Returns a string starting with 'Success:' or 'Error:'."
  (let* ((expanded-path (expand-file-name filepath))
         (buf (get-file-buffer expanded-path)))
    (condition-case err
        (progn
          (make-directory (file-name-directory expanded-path) t)
          (if buf
              ;; File is open in Emacs: write to the active buffer and save.
              ;; This bypasses file-lock errors and "changed on disk" desyncs.
              (with-current-buffer buf
                (erase-buffer)
                (insert content)
                (save-buffer))
            ;; File is closed: atomic write via temp+rename
            (let ((tmp-file (make-temp-file "gptel-write-")))
              (with-temp-file tmp-file
                (insert content))
              (rename-file tmp-file expanded-path t)))
          (format "Success: File written to '%s'" expanded-path))
      (error (format "Error: Failed to write file to '%s'. Emacs says: %s"
                     expanded-path (error-message-string err))))))

(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "write_file"
  :description "Create a new file or completely overwrite an existing file with new text content. Use this to save new agent profiles or rewrite configurations."
  :args (list '(:name "filepath" :type "string" :description "Absolute path to the destination file.")
              '(:name "content" :type "string" :description "The full text content to write into the file."))
  :function #'my-gptel--fs-write-file))

;;; --- append_file ---

(defun my-gptel--fs-append-file (filepath content)
  "Append CONTENT to the end of FILEPATH.
If the file exists and does not end with a newline, one is prepended.
If the file does not exist, it is created.
Returns a string starting with 'Success:' or 'Error:'."
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
        ;; Direct append: write-region with append flag preserves existing content.
        ;; (Atomic temp+rename would require reading entire file into memory first,
        ;; which is wasteful and was the root cause of the data-loss bug.)
        (write-region (concat prefix content) nil expanded-path t 'silent)
        (format "Success: Content appended to '%s'" expanded-path))
    (error (format "Error: Failed to append to '%s'. Emacs says: %s"
                   filepath (error-message-string err)))))

(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "append_file"
  :description "Append text content to the end of an existing file. Use this to add new notes, logs, or subheadings to a file without erasing its current contents. Automatically prepends a newline if the file does not already end with one, ensuring appended content always starts on a fresh line."
  :args (list '(:name "filepath" :type "string" :description "Absolute path to the file.")
              '(:name "content" :type "string" :description "The text content to add to the end of the file."))
  :function #'my-gptel--fs-append-file))

(provide 'fs_tools)