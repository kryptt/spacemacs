(defun unison//start-ucm (port)
  "Generate the Unison ucm startup command"
  `(,unison-ucm-bin "headless" "--port" ,(number-to-string port)))

(defun unison//universal-ucm ()
  "conditionally discover how to run ucm"
  (list
   :connect (lambda (filter sentinel name _environment-fn _workspace)
              (let* ((client (if (unison//server-running-p unison-ucm-host unison-ucm-port)
                                 (unison//reuse-ucm)
                               (unison//reuse-ucm) ))
                     (connect (plist-get client :connect)))

                (connect filter sentinel name _environment-fn _workspace)))
   :test? (lambda () t)))

(defun unison//run-ucm ()
  "Similar to lsp-tcp-connection"
  (let* ((host "localhost")
         (port (lsp--find-available-port host (cl-incf lsp--tcp-port)))
         (test-fn (lambda () (unison//server-running-p host port))))

    (list
     :connect (lambda (filter sentinel name environment-fn _workspace)
                (let* ((process-environment
                        (lsp--compute-process-environment environment-fn))
                       (proc (make-process :name name :connection-type 'pipe :coding 'no-conversion :command (unison//start-ucm port) :sentinel sentinel :stderr (format "+%s::stderr*" name) :noquery t))
                       (tcp-proc (lsp--open-network-stream host port (concat name "::tcp"))))

                  (set-process-query-on-exit-flag proc nil)
                  (set-process-filter tcp-proc filter)
                  (set-process-sentinel tcp-proc sentinel)
                  (cons tcp-proc proc)))
     :test? test-fn)))

(defun unison//reuse-ucm ()
  "Simply re-use an existing ucm connection"
  (list
   :connect (lambda (filter sentinel name _environment-fn _workspace)
              (let* ((host unison-ucm-host)
                     (port unison-ucm-port)
                     (tcp-proc (lsp--open-network-stream host port (concat name "::tcp"))))

                (set-process-query-on-exit-flag tcp-proc nil)
                (set-process-filter tcp-proc filter)
                (set-process-sentinel tcp-proc sentinel)
                (cons tcp-proc tcp-proc)))
   :test? (lambda () (unison//server-running-p unison-ucm-host unison-ucm-port))))

(defun unison//server-running-p (host port)
  "Check if a Unison server is already running on the given port"
  (condition-case nil
      (progn
        (delete-process
         (make-network-process
          :name "unison-port-check"
          :host host
          :service port))
        t)
    (error nil)))
