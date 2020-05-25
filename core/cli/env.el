;;; core/cli/env.el -*- lexical-binding: t; -*-

(defcli! env
    ((allow      ["-a" "--allow" regexp]  "An envvar whitelist regexp")
     (reject     ["-r" "--reject" regexp] "An envvar blacklist regexp")
     (clear-p    ["-c" "--clear"] "Clear and delete your envvar file")
     (outputfile ["-o" PATH]
    "Generate the envvar file at PATH. Envvar files that aren't in
`doom-env-file' won't be loaded automatically at startup. You will need to load
them manually from your private config with the `doom-load-envvars-file'
function."))
  "Creates or regenerates your envvars file.

The envvars file is created by scraping the current shell environment into
newline-delimited KEY=VALUE pairs. Typically by running '$SHELL -ic env' (or
'$SHELL -c set' on windows). Doom loads this file at startup (if it exists) to
ensure Emacs mirrors your shell environment (particularly to ensure PATH and
SHELL are correctly set).

This is useful in cases where you cannot guarantee that Emacs (or the daemon)
will be launched from the correct environment (e.g. on MacOS or through certain
app launchers on Linux).

This file is automatically regenerated when you run this command or 'doom sync'.
However, 'doom sync' will only regenerate this file if it exists.

Why this over exec-path-from-shell?

  1. `exec-path-from-shell' spawns (at least) one process at startup to scrape
     your shell environment. This can be arbitrarily slow depending on the
     user's shell configuration. A single program (like pyenv or nvm) or config
     framework (like oh-my-zsh) could undo all of Doom's startup optimizations
     in one fell swoop.

  2. `exec-path-from-shell' only scrapes some state from your shell. You have to
     be proactive in order to get it to capture all the envvars relevant to your
     development environment.

     I'd rather it inherit your shell environment /correctly/ (and /completely/)
     or not at all. It frontloads the debugging process rather than hiding it
     until you least want to deal with it."
  (let ((env-file (expand-file-name (or outputfile doom-env-file))))
    (cond (clear-p
           (unless (file-exists-p env-file)
             (user-error! "%S does not exist to be cleared"
                          (path env-file)))
           (delete-file env-file)
           (print! (success "Successfully deleted %S")
                   (path env-file)))

          ((and args (not (or allow reject)))
           (user-error "I don't understand 'doom env %s'"
                       (string-join args " ")))

          ((doom-cli-reload-env-file
            'force env-file (list allow) (list reject))))))


;;
;; Helpers

(defvar doom-env-blacklist
  '("^DBUS_SESSION_BUS_ADDRESS$"
    "^GPG_AGENT_INFO$" "^\\(SSH\\|GPG\\)_TTY$"
    "^SSH_\\(AUTH_SOCK\\|AGENT_PID\\)$"
    "^HOME$" "^PWD$" "^PS1$" "^R?PROMPT$" "^TERM$"
    ;; Doom envvars
    "^DEBUG$" "^INSECURE$" "^YES$" "^__")
  "Environment variables to not save in `doom-env-file'.

Each string is a regexp, matched against variable names to omit from
`doom-env-file'.")

(defvar doom-env-whitelist '()
  "A whitelist for envvars to save in `doom-env-file'.

This overrules `doom-env-ignored-vars'. Each string is a regexp, matched against
variable names to omit from `doom-env-file'.")

(defun doom-cli-reload-env-file (&optional force-p env-file whitelist blacklist)
  "Generates `doom-env-file', if it doesn't exist (or if FORCE-P).

This scrapes the variables from your shell environment by running
`doom-env-executable' through `shell-file-name' with `doom-env-switches'. By
default, on Linux, this is '$SHELL -ic /usr/bin/env'. Variables in
`doom-env-ignored-vars' are removed."
  (let ((env-file (if env-file (expand-file-name env-file) doom-env-file))
        (process-environment doom--initial-process-environment))
    (when (or force-p (not (file-exists-p env-file)))
      (with-temp-file env-file
        (setq-local coding-system-for-write 'utf-8)
        (print! (start "%s envvars file at %S")
                (if (file-exists-p env-file)
                    "Regenerating"
                  "Generating")
                (path env-file))
        (print-group!
         (when doom-interactive-p
           (user-error "'doom env' must be run on the command line, not an interactive session"))
         (goto-char (point-min))
         (insert
          (concat
           "# -*- mode: sh -*-\n"
           "# ---------------------------------------------------------------------------\n"
           "# This file was auto-generated by `doom env'. It contains a list of environment\n"
           "# variables scraped from your default shell (excluding variables blacklisted\n"
           "# in doom-env-ignored-vars).\n"
           "#\n"
           (if (file-equal-p env-file doom-env-file)
               (concat "# It is NOT safe to edit this file. Changes will be overwritten next time you\n"
                       "# run 'doom sync'. To create a safe-to-edit envvar file use:\n#\n"
                       "#   doom env -o ~/.doom.d/myenv\n#\n"
                       "# And load it with (doom-load-envvars-file \"~/.doom.d/myenv\").\n")
             (concat "# This file is safe to edit by hand, but remember to preserve the null bytes at\n"
                     "# the end of each line! needs to be loaded manually with:\n#\n"
                     "#   (doom-load-envvars-file \"path/to/this/file\")\n#\n"
                     "# Use 'doom env -o path/to/this/file' to regenerate it."))
           "# ---------------------------------------------------------------------------\n\0\n"))
         ;; We assume that this noninteractive session was spawned from the
         ;; user's interactive shell, therefore we just dump
         ;; `process-environment' to a file.
         (dolist (env process-environment)
           (if (cl-find-if (doom-rpartial #'string-match-p (car (split-string env "=")))
                           (remq nil (append blacklist doom-env-blacklist)))
               (if (not (cl-find-if (doom-rpartial #'string-match-p (car (split-string env "=")))
                                    (remq nil (append whitelist doom-env-whitelist))))
                   (print! (info "Ignoring %s") env)
                 (print! (info "Whitelisted %s") env)
                 (insert env "\0\n"))
             (insert env "\0\n")))
         (print! (success "Successfully generated %S")
                 (path env-file))
         t)))))
