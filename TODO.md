# TODO

## Bugs

### reload_os does not fully reload memory_tools.el
- **Date discovered:** 2026-06-22
- **Symptom:** After modifying memory feature code and running `reload_os`,
  triggering memory summarization (C-c m) fails with a timeout. Restarting the
  container fixes it, suggesting something in the reload path is not properly
  re-evaluating or re-registering the memory tools.
- **Suspected cause:** `load init-path nil t` may not fully re-evaluate
  `with-eval-after-load` blocks, `defcustom` definitions, or keymap
  registrations in `memory_tools.el`. The `load` function with `nil nosuffix`
  may also be using cached byte-compiled versions.
- **Investigation needed:**
  - Check if `load` is picking up stale `.elc` files instead of source `.el`.
  - Verify `with-eval-after-load 'gptel` blocks re-execute on reload.
  - Consider using `load-file` or explicit `eval-buffer` instead of `load`.
  - Check if `defcustom` forms are skipped on reload because the variable
    already has a value (custom-set-variables interference).
  - The `my-gptel-memory-call-ollama` function uses `gptel-backend-host`
    which is buffer-local -- after reload, the backend variable may not be
    set in the buffer where the tool runs.
- **Priority:** Medium (workaround exists: container restart)

## Features

### Elisp checker tool
- **Status:** In progress (2026-06-22)
- **Description:** Tool to check .el files for syntax errors, unbalanced
  parentheses, and byte-compilation warnings without modifying the file.