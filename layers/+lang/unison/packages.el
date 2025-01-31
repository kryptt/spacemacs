;;; packages.el --- Unison layer layers File for Spacemacs
;;
;; Copyright (c) 2012-2024 Sylvain Benner & Contributors
;;
;; Author: Rodolfo Hansen <kryptt@gmail.com>
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

(defconst unison-packages
  '(
    lsp
    (unison-ts-mode :location (recipe :fetcher github :repo "fmguerreiro/unison-ts-mode"))))

(defun unison/init-unison-ts-mode ()
  (use-package unison-ts-mode
    :defer t
    :init
    (require 'lsp-mode)
    (setq treesit-language-source-alist '((unison "https://github.com/fmguerreiro/tree-sitter-unison-kylegoetz" "build/include-parser-in-src-control")))
    :config
    (add-to-list 'lsp-language-id-configuration
                 '(unison-ts-mode . "unisonlang"))
    (setq-local lsp-tcp-connection-timeout 10)
    (lsp-register-client
     (make-lsp-client
      :new-connection (unison//universal-ucm)
      :major-modes '(unison-ts-mode)
      :activation-fn (lsp-activate-on "unisonlang")
      :server-id 'unisonlang))
    ))
