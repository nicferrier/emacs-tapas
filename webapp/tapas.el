;;; tapas.el -- a webapp presenting the emacslisp tapas

(require 'elnode)

(elnode-app tapas-root creole cl)

(defconst tapas-docroot
  (file-name-as-directory
   (expand-file-name (concat tapas-root "../creole-source"))))

(defconst tapas-indexroot
  (file-name-as-directory
   (expand-file-name (concat tapas-root "../indexes"))))

(defconst tapas-embed-handlers
  '(("include" . creole-include-handler)
    ("youtube" . creole-youtube-handler)))

(defun tapas-resolver (name)
  name)

(defmacro with-creole-embeds (embed-list &rest code)
  (declare (indent 1))
  `(let ((creole-embed-handlers ,embed-list))
     (let ((creole-link-resolver-fn 'tapas-resolver))
       ,@code)))

(defun tapas-make-page (index-file)
  (with-creole-embeds tapas-embed-handlers
    (let ((struct
           (creole-structure
            (creole-tokenize
             (find-file-noselect index-file)))))
      (loop for e in struct
         collect (if (eq 'para (car e))
                     (cons 'para (creole-block-parse (cdr e)))
                     e)))))

(defun tapas-creole->bootstrap (struct)
  "Transform STRUCT, a creole structure, into something bootstrapable.

HTML DIV elements are hacked into the structure wherever we find
an HR element.  The HR elements are retained."
  (noflet ((heading->section-id (heading)
             (format
              "%s-row"
              (replace-regexp-in-string
               "[ ?]" "-" (cdr heading)))))
    (let ((tx
           (loop for e in struct
              append
                (if (eq (car e) 'heading2)
                    (list
                     `(plugin-html
                       . ,(format
                           "</div></div></div>
<div class=\"section\" id=\"%s\">
<div class=\"container\">
<div class=\"row\">" (heading->section-id e))) e)
                    ;; Else just...
                    (list e)))))
      (append
       '((plugin-html
          . "<div class=\"section\" id=\"sec-top\">
<div class=\"container\">
<div class=\"row\">"))
       tx
       '((plugin-html . "</div></div></div><footer>")
         (ul
          "(C) 2013 Nic Ferrier"
          "[[/terms|terms]]"
          "[[/contact|contact]]")
         (plugin-html . "</footer>"))))))

(defun tapas-creole (creole-file destination &optional css)
  "Abstract the creole rendering to HTML a little."
  (interactive
   (list
    (concat tapas-indexroot "main.creole")
    (get-buffer-create "*testcreole*")))
  (creole-wiki
   creole-file
   :destination destination
   :structure-transform-fn 'tapas-creole->bootstrap
   :doctype 'html5
   :css (list "/-/bootstrap/css/bootstrap.css"
              "/-/common.css"
              (case css
                (:main "/-/main.css")
                (:index "/-/index.css")
                (t "/-/episode.css"))))
  (when (called-interactively-p 'interactive)
    (switch-to-buffer destination)))

(defun tapas-creole-page (httpcon filename &optional css)
  (with-creole-embeds tapas-embed-handlers
    (elnode-http-start httpcon 200 '("Content-type" . "text/html"))
    (with-stdout-to-elnode httpcon
        (tapas-creole filename t css))))

(defun tapas-episode (httpcon)
  "Episode server."
  (noflet ((elnode-http-mapping (httpcon which)
             (concat (funcall this-fn httpcon 1) ".creole")))
    (elnode-docroot-for tapas-docroot
        with targetfile
        on httpcon
        do
        (tapas-creole-page httpcon targetfile))))

;; Might do for the index page
(defun tapas-main (httpcon)
  (let ((page (concat tapas-indexroot "main.creole")))
    (tapas-creole-page httpcon page :main)))

(defconst tapas-assets-server
  (elnode-webserver-handler-maker
   (file-name-as-directory
    (expand-file-name (concat tapas-root "../assets"))))
  "Webserver for static assets.")

(defun tapas-router (httpcon)
  (elnode-hostpath-dispatcher
   httpcon
   `(("^[^/]+//$" . tapas-main)
     ("^[^/]+//favicon.ico"
      . ,(elnode-make-send-file
          (concat tapas-root "../assets/olive.ico")))
     ("^[^/]+//-/\\(.*\\)" . ,tapas-assets-server)
     ("^[^/]+//episode/\\(.*\\)" . tapas-episode))))

(defun tapas-start ()
  (interactive)
  (elnode-start 'tapas-router :port 8006))

;;; tapas.el ends here
