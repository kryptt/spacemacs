;;; funcs.el --- Devcontainer Layer functions File for Spacemacs  -*- lexical-binding: t; -*-
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

(defun spacemacs//devcontainer-container-info (project-root)
  "Return the container info for PROJECT-ROOT, or nil if not running.
Returns a cons cell (container-id . workspace-folder)."
  (gethash project-root spacemacs--devcontainer-active-containers))

(defun spacemacs//devcontainer-container-id (project-root)
  "Return the container ID for PROJECT-ROOT, or nil if not running."
  (car (spacemacs//devcontainer-container-info project-root)))

(defun spacemacs//devcontainer-workspace-folder (project-root)
  "Return the workspace folder for PROJECT-ROOT, or \"/workspaces\"."
  (or (cdr (spacemacs//devcontainer-container-info project-root))
      "/workspaces"))

(defun spacemacs//devcontainer-running-p (&optional project-root)
  "Return non-nil if a devcontainer is active for PROJECT-ROOT."
  (let ((root (or project-root (spacemacs//devcontainer-project-root))))
    (and root (spacemacs//devcontainer-container-id root))))

;; --- Cache persistence ---

(defun spacemacs//devcontainer-load-cache ()
  "Load per-project devcontainer choices from cache file.
Returns an alist of (project-root . choice) where choice is `yes' or `no'."
  (when (file-exists-p devcontainer-cache-file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents devcontainer-cache-file)
          (read (current-buffer)))
      (error
       (message "Warning: devcontainer cache file is corrupted, ignoring")
       nil))))

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

(defun spacemacs//devcontainer-get-buffer (project-root)
  "Return the devcontainer output buffer for PROJECT-ROOT, creating if needed."
  (get-buffer-create
   (format "*devcontainer:%s*"
           (file-name-nondirectory (directory-file-name project-root)))))

(defun spacemacs//devcontainer-run-async (args callback project-root)
  "Run devcontainer CLI with ARGS asynchronously.
Output goes to a per-project *devcontainer:PROJECT-ROOT* buffer.
CALLBACK is called with the process exit code when complete.
PROJECT-ROOT is used as --workspace-folder."
  (spacemacs//devcontainer-check-prerequisites)
  (let* ((cli (spacemacs//devcontainer-cli-executable))
         (full-args (append args (list "--workspace-folder" project-root)))
         (buf (spacemacs//devcontainer-get-buffer project-root))
         (proc-name (format "devcontainer<%s>"
                            (file-name-nondirectory
                             (directory-file-name project-root))))
         (cmd (append (list cli) full-args)))
    (with-current-buffer buf
      (erase-buffer)
      (insert (format "--- %s: devcontainer %s ---\n"
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
    (save-excursion
      (goto-char (point-min))
      (let ((json-result nil))
        (while (re-search-forward "^{.*}$" nil t)
          (condition-case nil
              (setq json-result (json-read-from-string (match-string 0)))
            (error nil)))
        json-result))))

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
       (let ((buf (spacemacs//devcontainer-get-buffer root)))
         (if (/= exit-code 0)
             (progn
               (display-buffer buf)
               (message "devcontainer up failed (exit code %d). See %s buffer."
                        exit-code (buffer-name buf)))
           (let* ((result (spacemacs//devcontainer-parse-up-output buf))
                  (container-id (alist-get 'containerId result))
                  (workspace-folder (or (alist-get 'remoteWorkspaceFolder result)
                                        "/workspaces")))
             (if (not container-id)
                 (progn
                   (display-buffer buf)
                   (message "Could not determine container ID. See %s buffer."
                            (buffer-name buf)))
               (puthash root (cons container-id workspace-folder)
                        spacemacs--devcontainer-active-containers)
               (let ((tramp-path (format "/%s:%s:%s" tramp-method container-id workspace-folder)))
                 (message "Connected to devcontainer: %s" tramp-path)
                 (dired tramp-path)))))))
     root)))

(defun spacemacs/devcontainer-stop (&optional project-root)
  "Stop the devcontainer for PROJECT-ROOT.
Uses docker/podman directly since the devcontainer CLI has no stop command."
  (interactive)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root)))
         (container-id (and root (spacemacs//devcontainer-container-id root)))
         (runtime (spacemacs//devcontainer-runtime))
         (runtime-path (pcase runtime
                         ("docker" (spacemacs//devcontainer-docker-executable))
                         ("podman" (spacemacs//devcontainer-podman-executable)))))
    (unless root (user-error "Not in a project"))
    (unless container-id
      (user-error "No running devcontainer for this project"))
    (unless runtime-path
      (user-error "No container runtime available"))
    (message "Stopping devcontainer for %s..." (file-name-nondirectory (directory-file-name root)))
    (let* ((buf (spacemacs//devcontainer-get-buffer root))
           (proc (make-process
                  :name (format "devcontainer-stop<%s>"
                                (file-name-nondirectory (directory-file-name root)))
                  :buffer buf
                  :command (list runtime-path "stop" container-id)
                  :sentinel (lambda (proc event)
                              (when (memq (process-status proc) '(exit signal))
                                (let ((exit-code (process-exit-status proc)))
                                  (if (/= exit-code 0)
                                      (message "devcontainer stop failed (exit code %d)" exit-code)
                                    (remhash root spacemacs--devcontainer-active-containers)
                                    (message "Devcontainer stopped."))))))))
      proc)))

(defun spacemacs/devcontainer-rebuild (&optional project-root)
  "Rebuild and reconnect to the devcontainer for PROJECT-ROOT.
Uses `devcontainer up --remove-existing-container --build-no-cache'."
  (interactive)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root)))
         (tramp-method (spacemacs//devcontainer-tramp-method)))
    (unless root (user-error "Not in a project"))
    (unless (spacemacs//devcontainer-has-config-p root)
      (user-error "No devcontainer.json found in %s" root))
    (unless tramp-method
      (user-error "No container runtime available"))
    (remhash root spacemacs--devcontainer-active-containers)
    (message "Rebuilding devcontainer for %s..." (file-name-nondirectory (directory-file-name root)))
    (spacemacs//devcontainer-run-async
     (list "up" "--remove-existing-container" "--build-no-cache" "--log-format" "json")
     (lambda (exit-code)
       (let ((buf (spacemacs//devcontainer-get-buffer root)))
         (if (/= exit-code 0)
             (progn
               (display-buffer buf)
               (message "devcontainer rebuild failed (exit code %d). See %s buffer."
                        exit-code (buffer-name buf)))
           (let* ((result (spacemacs//devcontainer-parse-up-output buf))
                  (container-id (alist-get 'containerId result))
                  (workspace-folder (or (alist-get 'remoteWorkspaceFolder result)
                                        "/workspaces")))
             (if (not container-id)
                 (progn
                   (display-buffer buf)
                   (message "Could not determine container ID. See %s buffer."
                            (buffer-name buf)))
               (puthash root (cons container-id workspace-folder)
                        spacemacs--devcontainer-active-containers)
               (let ((tramp-path (format "/%s:%s:%s" tramp-method container-id workspace-folder)))
                 (message "Rebuilt and connected to devcontainer: %s" tramp-path)
                 (dired tramp-path)))))))
     root)))

(defun spacemacs/devcontainer-terminal (&optional project-root)
  "Open a terminal inside the devcontainer for PROJECT-ROOT."
  (interactive)
  (let* ((root (or project-root (spacemacs//devcontainer-project-root)))
         (container-id (and root (spacemacs//devcontainer-container-id root)))
         (tramp-method (spacemacs//devcontainer-tramp-method))
         (workspace-folder (spacemacs//devcontainer-workspace-folder root)))
    (unless container-id
      (user-error "No running devcontainer for this project. Use SPC C-d o to start one"))
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
    (when (fboundp 'tramp-cleanup-connection)
      (ignore-errors
        (tramp-cleanup-connection
         (tramp-dissect-file-name (format "/%s:%s:/" tramp-method container-id)))))
    (remhash root spacemacs--devcontainer-active-containers)
    (message "Disconnected from devcontainer (container still running).")))

(defun spacemacs/devcontainer-log (&optional project-root)
  "Show the devcontainer output buffer for PROJECT-ROOT."
  (interactive)
  (let ((root (or project-root (spacemacs//devcontainer-project-root))))
    (unless root (user-error "Not in a project"))
    (display-buffer (spacemacs//devcontainer-get-buffer root))))

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
              nil)
             (t
              (if (or (not devcontainer-prompt-to-open)
                      (y-or-n-p (format "Project %s has a devcontainer. Open in container? "
                                        (file-name-nondirectory (directory-file-name root)))))
                  (progn
                    (spacemacs//devcontainer-cache-set root 'yes)
                    (spacemacs/devcontainer-open root))
                (spacemacs//devcontainer-cache-set root 'no))))))))))
