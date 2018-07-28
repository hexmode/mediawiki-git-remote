((cperl-mode . ((eval . (let ((this-dir (car (dir-locals-find-file "."))))
                          (setenv "PERL5LIB" (concat this-dir "/lib:" this-dir "/localcpan"))
                          (setenv "GIT_EXEC_PATH"
                                  (concat this-dir ":"
                                          (shell-command-to-string "git --exec-path"))))))))
