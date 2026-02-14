;;; packages.el --- Devcontainer Layer packages File for Spacemacs  -*- lexical-binding: t; -*-
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
  '((devcontainer :location (recipe :fetcher github
                                    :repo "johannes-mueller/devcontainer.el"))))

(defun devcontainer/init-devcontainer ()
  (use-package devcontainer
    :defer t
    :init
    (spacemacs/declare-prefix "C-d" "devcontainer")
    (spacemacs/set-leader-keys
      "C-d u" 'devcontainer-up
      "C-d r" 'devcontainer-restart
      "C-d R" 'devcontainer-rebuild-and-restart
      "C-d k" 'devcontainer-kill-container
      "C-d x" 'devcontainer-execute-command
      "C-d X" 'devcontainer-execute-command-interactive
      "C-d t" 'devcontainer-term
      "C-d d" 'devcontainer-tramp-dired
      "C-d m" 'devcontainer-mode)))
