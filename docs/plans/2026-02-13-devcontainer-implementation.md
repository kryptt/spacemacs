# Devcontainer Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a Spacemacs layer at `layers/+tools/devcontainer/` that wraps the `devcontainer` CLI to provide VS Code-like devcontainer support via TRAMP.

**Architecture:** Thin CLI wrapper. The `devcontainer` CLI handles all spec-level work (build, up, exec, JSON parsing). Elisp handles project detection, TRAMP wiring, keybindings, and async process management. All container access is via TRAMP (`/docker:` or `/podman:` methods).

**Tech Stack:** Emacs Lisp, Spacemacs layer API, TRAMP, docker-tramp, `@devcontainers/cli`, projectile.

**Design doc:** `docs/plans/2026-02-13-devcontainer-design.md`

**Reference layers:** Study `layers/+tools/docker/` for packaging patterns, `layers/+tools/vagrant/` for TRAMP integration patterns, `layers/+tools/dap/` for complex keybinding patterns.

---

### Task 1: Create layer skeleton with config.el

**Files:**
- Create: `layers/+tools/devcontainer/config.el`

**Step 1: Create directory and config.el**

Create `layers/+tools/devcontainer/config.el` with all defcustom variables. Follow Spacemacs convention: use `defvar` for layer variables (so users can override via `:variables` in dotspacemacs-configuration-layers).

```elisp
;;; config.el --- Devcontainer Layer Configuration File for Spacemacs  -*- lexical-binding: nil; -*-
;;
;; Copyright (c) 2012-2025 Sylvain Benner & Contributors
;;
;; Author: Rodolfo Hansen
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


;; Variables

(defvar devcontainer-cli-path nil
  "Path to the devcontainer CLI executable.
If nil, `executable-find' is used to locate it at runtime.")

(defvar devcontainer-docker-path nil
  "Path to the docker CLI executable.
If nil, `executable-find' is used to locate it at runtime.")

(defvar devcontainer-podman-path nil
  "Path to the podman CLI executable.
If nil, `executable-find' is used to locate it at runtime.")

(defvar devcontainer-preferred-runtime 'auto
  "Preferred container runtime.
Possible values are `auto', `docker', or `podman'.
When set to `auto', docker is preferred if both are available.")

(defvar devcontainer-auto-detect t
  "If non-nil, check for devcontainer.json when switching projects.")

(defvar devcontainer-prompt-to-open t
  "If non-nil, prompt before opening a project in its devcontainer.
If nil, auto-opens without asking.")

(defvar devcontainer-cache-file
  (expand-file-name ".cache/devcontainer-projects" spacemacs-cache-directory)
  "File to persist per-project devcontainer choices.")

;; Internal state

(defvar spacemacs--devcontainer-active-containers (make-hash-table :test 'equal)
  "Hash table mapping project root paths to container IDs.")
```

**Step 2: Verify the file loads without errors**

Run: Open Emacs, evaluate `(load-file "layers/+tools/devcontainer/config.el")` in `*scratch*`
Expected: No errors, variables are defined.

**Step 3: Commit**

```bash
git add layers/+tools/devcontainer/config.el
git commit -m "feat(devcontainer): add layer skeleton with config variables"
```

---

### Task 2: Core utility functions (runtime detection, devcontainer.json detection)

**Files:**
- Create: `layers/+tools/devcontainer/funcs.el`

**Step 1: Write runtime detection and devcontainer detection functions**

Create `layers/+tools/devcontainer/funcs.el`:

```elisp
;;; funcs.el --- Devcontainer Layer functions File for Spacemacs  -*- lexical-binding: nil; -*-
;;
;; Copyright (c) 2012-2025 Sylvain Benner & Contributors
;;
;; Author: Rodolfo Hansen
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


(require 'json)

;; --- Runtime detection ---

(defun spacemacs//devcontainer-cli-executable ()
  "Return path to devcontainer CLI, or nil if not found."
  (or devcontainer-cli-path (executable-find "devcontainer")))

(defun spacemacs//devcontainer-docker-executable ()
  "Return path to docker CLI, or nil if not found."
  (or devcontainer-docker-path (executable-find "docker")))

(defun spacemacs//devcontainer-podman-executable ()
  "Return path to podman CLI, or nil if not found."
  (or devcontainer-podman-path (executable-find "podman")))

(defun spacemacs//devcontainer-runtime ()
  "Return the container runtime to use: \"docker\" or \"podman\".
Returns nil if no runtime is available."
  (pcase devcontainer-preferred-runtime
    ('docker (when (spacemacs//devcontainer-docker-executable) "docker"))
    ('podman (when (spacemacs//devcontainer-podman-executable) "podman"))
    ('auto (cond
            ((spacemacs//devcontainer-docker-executable) "docker")
            ((spacemacs//devcontainer-podman-executable) "podman")
            (t nil)))))

(defun spacemacs//devcontainer-tramp-method ()
  "Return the TRAMP method string for the active runtime."
  (let ((runtime (spacemacs//devcontainer-runtime)))
    (pcase runtime
      ("docker" "docker")
      ("podman" "podman")
      (_ nil))))

(defun spacemacs//devcontainer-check-prerequisites ()
  "Check that devcontainer CLI and a container runtime are available.
Signals a user-error if anything is missing."
  (unless (spacemacs//devcontainer-cli-executable)
    (user-error "devcontainer CLI not found. Install via: npm install -g @devcontainers/cli"))
  (unless (spacemacs//devcontainer-runtime)
    (user-error "No container runtime found. Install docker or podman")))

;; --- Project detection ---

(defun spacemacs//devcontainer-project-root ()
  "Return the project root for the current buffer, or nil."
  (when (fboundp 'projectile-project-root)
    (projectile-project-root)))

(defun spacemacs//devcontainer-config-path (project-root)
  "Return the devcontainer config path for PROJECT-ROOT, or nil if none exists.
Checks for .devcontainer/devcontainer.json and .devcontainer.json."
  (let ((dir-config (expand-file-name ".devcontainer/devcontainer.json" project-root))
        (root-config (expand-file-name ".devcontainer.json" project-root)))
    (cond
     ((file-exists-p dir-config) dir-config)
     ((file-exists-p root-config) root-config)
     (t nil))))

(defun spacemacs//devcontainer-has-config-p (&optional project-root)
  "Return non-nil if PROJECT-ROOT (or current project) has a devcontainer config."
  (let ((root (or project-root (spacemacs//devcontainer-project-root))))
    (and root (spacemacs//devcontainer-config-path root))))

;; --- Container state ---

(defun spacemacs//devcontainer-container-id (project-root)
  "Return the container ID for PROJECT-ROOT, or nil if not running."
  (gethash project-root spacemacs--devcontainer-active-containers))

(defun spacemacs//devcontainer-running-p (&optional project-root)
  "Return non-nil if a devcontainer is active for PROJECT-ROOT."
  (let ((root (or project-root (spacemacs//devcontainer-project-root))))
    (and root (spacemacs//devcontainer-container-id root))))

;; --- Cache persistence ---

(defun spacemacs//devcontainer-load-cache ()
  "Load per-project devcontainer choices from cache file.
Returns an alist of (project-root . choice) where choice is `yes' or `no'."
  (when (file-exists-p devcontainer-cache-file)
    (with-temp-buffer
      (insert-file-contents devcontainer-cache-file)
      (read (current-buffer)))))

(defun spacemacs//devcontainer-save-cache (cache)
  "Save CACHE alist to the cache file."
  (let ((dir (file-name-directory devcontainer-cache-file)))
    (unless (file-directory-p dir)
      (make-directory dir t)))
  (with-temp-file devcontainer-cache-file
    (prin1 cache (current-buffer))))

(defun spacemacs//devcontainer-cache-get (project-root)
  "Return cached choice for PROJECT-ROOT, or nil if not cached."
  (alist-get project-root (spacemacs//devcontainer-load-cache) nil nil #'equal))

(defun spacemacs//devcontainer-cache-set (project-root choice)
  "Set cached CHOICE for PROJECT-ROOT. CHOICE should be `yes' or `no'."
  (let* ((cache (spacemacs//devcontainer-load-cache))
         (updated (cons (cons project-root choice)
                        (assoc-delete-all project-root cache #'equal))))
    (spacemacs//devcontainer-save-cache updated)))

;; --- Async CLI wrapper ---

(defun spacemacs//devcontainer-get-buffer ()
  "Return the *devcontainer* output buffer, creating if needed."
  (get-buffer-create "*devcontainer*"))

(defun spacemacs//devcontainer-run-async (args callback &optional project-root)
  "Run devcontainer CLI with ARGS asynchronously.
Output goes to *devcontainer* buffer. CALLBACK is called with
the process exit code when complete. PROJECT-ROOT is used as
--workspace-folder if provided."
  (spacemacs//devcontainer-check-prerequisites)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root)))
         (cli (spacemacs//devcontainer-cli-executable))
         (full-args (if root
                        (append args (list "--workspace-folder" root))
                      args))
         (buf (spacemacs//devcontainer-get-buffer))
         (proc-name "devcontainer")
         (cmd (append (list cli) full-args)))
    (with-current-buffer buf
      (goto-char (point-max))
      (insert (format "\n--- %s: devcontainer %s ---\n"
                      (format-time-string "%H:%M:%S")
                      (string-join full-args " "))))
    (let ((proc (make-process
                 :name proc-name
                 :buffer buf
                 :command cmd
                 :sentinel (lambda (proc event)
                             (when (memq (process-status proc) '(exit signal))
                               (let ((exit-code (process-exit-status proc)))
                                 (with-current-buffer (process-buffer proc)
                                   (goto-char (point-max))
                                   (insert (format "\n--- exited with code %d ---\n" exit-code)))
                                 (when callback
                                   (funcall callback exit-code))))))))
      proc)))

;; --- Container lifecycle ---

(defun spacemacs//devcontainer-parse-up-output (buffer)
  "Parse the devcontainer up JSON output from BUFFER.
Returns an alist with keys like `containerId' and `remoteWorkspaceFolder'."
  (with-current-buffer buffer
    (goto-char (point-min))
    ;; Find the last JSON object in the output (devcontainer up prints
    ;; progress lines then a final JSON result)
    (let ((json-result nil))
      (while (re-search-forward "^{.*}$" nil t)
        (condition-case nil
            (setq json-result (json-read-from-string (match-string 0)))
          (error nil)))
      json-result)))

(defun spacemacs/devcontainer-open (&optional project-root)
  "Build (if needed) and connect to the devcontainer for PROJECT-ROOT."
  (interactive)
  (spacemacs//devcontainer-check-prerequisites)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root)))
         (tramp-method (spacemacs//devcontainer-tramp-method)))
    (unless root
      (user-error "Not in a project"))
    (unless (spacemacs//devcontainer-has-config-p root)
      (user-error "No devcontainer.json found in %s" root))
    (unless tramp-method
      (user-error "No container runtime available"))
    (message "Starting devcontainer for %s..." (file-name-nondirectory (directory-file-name root)))
    (spacemacs//devcontainer-run-async
     (list "up" "--log-format" "json")
     (lambda (exit-code)
       (if (/= exit-code 0)
           (progn
             (display-buffer (spacemacs//devcontainer-get-buffer))
             (message "devcontainer up failed (exit code %d). See *devcontainer* buffer." exit-code))
         (let* ((result (spacemacs//devcontainer-parse-up-output
                         (spacemacs//devcontainer-get-buffer)))
                (container-id (alist-get 'containerId result))
                (workspace-folder (or (alist-get 'remoteWorkspaceFolder result)
                                      "/workspaces")))
           (if (not container-id)
               (progn
                 (display-buffer (spacemacs//devcontainer-get-buffer))
                 (message "Could not determine container ID. See *devcontainer* buffer."))
             ;; Store container ID
             (puthash root container-id spacemacs--devcontainer-active-containers)
             ;; Open project via TRAMP
             (let ((tramp-path (format "/%s:%s:%s" tramp-method container-id workspace-folder)))
               (message "Connected to devcontainer: %s" tramp-path)
               (dired tramp-path))))))
     root)))

(defun spacemacs/devcontainer-stop (&optional project-root)
  "Stop the devcontainer for PROJECT-ROOT."
  (interactive)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root))))
    (unless root (user-error "Not in a project"))
    (message "Stopping devcontainer for %s..." (file-name-nondirectory (directory-file-name root)))
    (spacemacs//devcontainer-run-async
     (list "stop")
     (lambda (exit-code)
       (if (/= exit-code 0)
           (message "devcontainer stop failed (exit code %d)" exit-code)
         (remhash root spacemacs--devcontainer-active-containers)
         (message "Devcontainer stopped.")))
     root)))

(defun spacemacs/devcontainer-rebuild (&optional project-root)
  "Rebuild and reconnect to the devcontainer for PROJECT-ROOT."
  (interactive)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root))))
    (unless root (user-error "Not in a project"))
    (remhash root spacemacs--devcontainer-active-containers)
    (message "Rebuilding devcontainer for %s..." (file-name-nondirectory (directory-file-name root)))
    (spacemacs//devcontainer-run-async
     (list "build" "--no-cache")
     (lambda (exit-code)
       (if (/= exit-code 0)
           (progn
             (display-buffer (spacemacs//devcontainer-get-buffer))
             (message "devcontainer build failed (exit code %d)" exit-code))
         (spacemacs/devcontainer-open root)))
     root)))

(defun spacemacs/devcontainer-terminal (&optional project-root)
  "Open a terminal inside the devcontainer for PROJECT-ROOT."
  (interactive)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root)))
         (container-id (and root (spacemacs//devcontainer-container-id root)))
         (tramp-method (spacemacs//devcontainer-tramp-method))
         (workspace-folder (or (ignore-errors
                                 (alist-get 'remoteWorkspaceFolder
                                            (spacemacs//devcontainer-parse-up-output
                                             (spacemacs//devcontainer-get-buffer))))
                               "/workspaces")))
    (unless container-id
      (user-error "No running devcontainer for this project. Use SPC d c o to start one"))
    (let ((default-directory (format "/%s:%s:%s" tramp-method container-id workspace-folder)))
      (if (fboundp 'vterm)
          (vterm (format "*devcontainer-term:%s*"
                         (file-name-nondirectory (directory-file-name root))))
        (shell (format "*devcontainer-shell:%s*"
                       (file-name-nondirectory (directory-file-name root))))))))

(defun spacemacs/devcontainer-disconnect (&optional project-root)
  "Disconnect from the devcontainer without stopping it."
  (interactive)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root)))
         (container-id (and root (spacemacs//devcontainer-container-id root)))
         (tramp-method (spacemacs//devcontainer-tramp-method)))
    (unless container-id
      (user-error "No active devcontainer for this project"))
    ;; Clean up TRAMP connections for this container
    (when (fboundp 'tramp-cleanup-connection)
      (ignore-errors
        (tramp-cleanup-connection
         (tramp-dissect-file-name (format "/%s:%s:/" tramp-method container-id)))))
    (remhash root spacemacs--devcontainer-active-containers)
    (message "Disconnected from devcontainer (container still running).")))

(defun spacemacs/devcontainer-log ()
  "Show the *devcontainer* output buffer."
  (interactive)
  (display-buffer (spacemacs//devcontainer-get-buffer)))

(defun spacemacs/devcontainer-info (&optional project-root)
  "Show devcontainer status and metadata for PROJECT-ROOT."
  (interactive)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root)))
         (container-id (and root (spacemacs//devcontainer-container-id root)))
         (config-path (and root (spacemacs//devcontainer-config-path root)))
         (runtime (spacemacs//devcontainer-runtime)))
    (message (concat
              (format "Project: %s\n" (or root "none"))
              (format "Config: %s\n" (or config-path "not found"))
              (format "Runtime: %s\n" (or runtime "none"))
              (format "Container: %s\n" (or container-id "not running"))
              (format "CLI: %s" (or (spacemacs//devcontainer-cli-executable) "not found"))))))

;; --- Project switch hook ---

(defun spacemacs//devcontainer-project-switch-hook ()
  "Hook run when switching projects via projectile.
Checks for devcontainer config and prompts to open."
  (when devcontainer-auto-detect
    (let ((root (spacemacs//devcontainer-project-root)))
      (when (and root (spacemacs//devcontainer-has-config-p root))
        (unless (spacemacs//devcontainer-running-p root)
          (let ((cached-choice (spacemacs//devcontainer-cache-get root)))
            (cond
             ((eq cached-choice 'yes)
              (spacemacs/devcontainer-open root))
             ((eq cached-choice 'no)
              nil) ; User previously said no
             (t
              (when (or (not devcontainer-prompt-to-open)
                        (y-or-n-p (format "Project %s has a devcontainer. Open in container? "
                                          (file-name-nondirectory (directory-file-name root)))))
                (spacemacs//devcontainer-cache-set root 'yes)
                (spacemacs/devcontainer-open root))))))))))
```

**Step 2: Verify the file loads without errors**

Run: Open Emacs, evaluate `(load-file "layers/+tools/devcontainer/funcs.el")` in `*scratch*`
Expected: No errors, functions are defined. Verify with `(describe-function 'spacemacs/devcontainer-open)`.

**Step 3: Commit**

```bash
git add layers/+tools/devcontainer/funcs.el
git commit -m "feat(devcontainer): add core functions - CLI wrapper, TRAMP wiring, detection"
```

---

### Task 3: Keybindings

**Files:**
- Create: `layers/+tools/devcontainer/keybindings.el`

**Step 1: Write keybindings.el**

```elisp
;;; keybindings.el --- Devcontainer Layer keybindings File for Spacemacs  -*- lexical-binding: nil; -*-
;;
;; Copyright (c) 2012-2025 Sylvain Benner & Contributors
;;
;; Author: Rodolfo Hansen
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


(spacemacs/declare-prefix "dc" "devcontainer")
(spacemacs/set-leader-keys
  "dco" 'spacemacs/devcontainer-open
  "dcs" 'spacemacs/devcontainer-stop
  "dcr" 'spacemacs/devcontainer-rebuild
  "dct" 'spacemacs/devcontainer-terminal
  "dcl" 'spacemacs/devcontainer-log
  "dcd" 'spacemacs/devcontainer-disconnect
  "dci" 'spacemacs/devcontainer-info)
```

**Step 2: Commit**

```bash
git add layers/+tools/devcontainer/keybindings.el
git commit -m "feat(devcontainer): add keybindings under SPC d c prefix"
```

---

### Task 4: Package declarations and layer dependencies

**Files:**
- Create: `layers/+tools/devcontainer/packages.el`
- Create: `layers/+tools/devcontainer/layers.el`

**Step 1: Write packages.el**

The devcontainer layer doesn't introduce new MELPA packages. It uses built-in Emacs features (TRAMP, json) and packages from other layers (docker-tramp, projectile). We declare an "owned" local package for our own code and post-init hooks for packages from other layers.

```elisp
;;; packages.el --- Devcontainer Layer packages File for Spacemacs  -*- lexical-binding: nil; -*-
;;
;; Copyright (c) 2012-2025 Sylvain Benner & Contributors
;;
;; Author: Rodolfo Hansen
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


(defconst devcontainer-packages
  '(projectile))

(defun devcontainer/post-init-projectile ()
  (add-hook 'projectile-after-switch-project-hook
            #'spacemacs//devcontainer-project-switch-hook))
```

**Step 2: Write layers.el**

```elisp
;;; layers.el --- Devcontainer Layer declarations File for Spacemacs  -*- lexical-binding: nil; -*-
;;
;; Copyright (c) 2012-2025 Sylvain Benner & Contributors
;;
;; Author: Rodolfo Hansen
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


(configuration-layer/declare-layer-dependencies '(docker))
```

**Step 3: Commit**

```bash
git add layers/+tools/devcontainer/packages.el layers/+tools/devcontainer/layers.el
git commit -m "feat(devcontainer): add package declarations and docker layer dependency"
```

---

### Task 5: Enable layer in .spacemacs and smoke test

**Files:**
- Modify: `~/.spacemacs` (add `devcontainer` to `dotspacemacs-configuration-layers`)

**Step 1: Add the layer**

In `~/.spacemacs`, in the `dotspacemacs-configuration-layers` list, add `devcontainer` near `docker`:

```elisp
     docker
     devcontainer
```

**Step 2: Smoke test**

Restart Emacs (`SPC q r`) and verify:
- No errors on startup
- `SPC d c` shows which-key menu with all 7 bindings
- `M-x spacemacs/devcontainer-info` runs and shows status
- `M-x spacemacs/devcontainer-open` on a non-devcontainer project shows "No devcontainer.json found" error

**Step 3: Commit**

```bash
git add ~/.spacemacs
git commit -m "feat(devcontainer): enable devcontainer layer"
```

---

### Task 6: Manual integration test with a real devcontainer project

**No files to modify** — this is a validation step.

**Step 1: Create a test project with devcontainer**

```bash
mkdir -p /tmp/devcontainer-test/.devcontainer
cat > /tmp/devcontainer-test/.devcontainer/devcontainer.json << 'EOF'
{
  "name": "Test Devcontainer",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu"
}
EOF
```

**Step 2: Test the full flow**

1. Open Emacs, navigate to `/tmp/devcontainer-test/` with projectile
2. Run `SPC d c o` — should build and start the container
3. Verify TRAMP connection opens (dired of container filesystem)
4. Run `SPC d c t` — should open a terminal in the container
5. Run `SPC d c i` — should show container info
6. Run `SPC d c d` — should disconnect TRAMP
7. Run `SPC d c s` — should stop the container
8. Switch to the project again — should be prompted to open in devcontainer
9. Choose yes — verify it connects automatically

**Step 3: Fix any issues found during testing**

Iterate on `funcs.el` as needed.

**Step 4: Commit any fixes**

```bash
git add -u
git commit -m "fix(devcontainer): address issues found in integration testing"
```
