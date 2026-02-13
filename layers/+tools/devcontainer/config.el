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
  (expand-file-name "devcontainer-projects" spacemacs-cache-directory)
  "File to persist per-project devcontainer choices.")

;; Internal state

(defvar spacemacs--devcontainer-active-containers (make-hash-table :test 'equal)
  "Hash table mapping project root paths to (container-id . workspace-folder) cons cells.")
