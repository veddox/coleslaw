(eval-when (:compile-toplevel :load-toplevel)
  (ql:quickload '(coleslaw cxml cl-ppcre local-time)))

(defpackage :coleslaw-import
  (:use :cl :cxml)
  (:import-from :coleslaw #:slugify
                          #:load-config
                          #:*config*
                          #:repo)
  (:import-from :local-time #:+short-month-names+)
  (:import-from :cl-ppcre #:regex-replace-all))

(in-package :coleslaw-import)

(defun node-val (name post)
  (flet ((value (node)
           (let ((child (dom:last-child node)))
             (when child (dom:data child)))))
    (let ((nodes (dom:get-elements-by-tag-name post name)))
      (if (string= "category" name)
          (loop for node across nodes collecting (value node))
          (when (plusp (length nodes)) (value (elt nodes 0)))))))

(defun get-timestamp (post)
  (destructuring-bind (day date month year time tz)
      (cl-ppcre:split " " (node-val "pubDate" post))
    (format nil "~a-~2,'0d-~2,'0d ~a" year (position month +short-month-names+
                                                     :test #'string=) date time)))

(defun import-post (post)
  (when (and (string= "publish" (node-val "wp:status" post)) ; is it public?
             (string= "post" (node-val "wp:post_type" post)) ; is it a post?
             (string>= (get-timestamp post) "2007-05"))
    (let ((content (node-val "content:encoded" post))
          (slug (slugify (node-val "title" post))))
      (when (string= "" slug)
        (error "No valid slug-title for post ~a." (get-timestamp post)))
      (export-post (node-val "title" post) (node-val "category" post)
                   (get-timestamp post) content
                   (format nil "~a.post" slug)))))

(defun export-post (title tags date content path)
  (with-open-file (out (merge-pathnames path (repo *config*))
                   :direction :output
                   :if-exists :supersede
                   :if-does-not-exist :create)
    ;; TODO: What other data/metadata should we write out?
    (format out ";;;;;~%")
    (format out "title: ~A~%" title)
    (format out "tags: ~A~%" (format nil "~{~A, ~}" tags))
    (format out "date: ~A~%" date)
    (format out "format: html~%") ; post format: html, md, rst, etc
    (format out ";;;;;~%")
    (format out "~A~%" (regex-replace-all (string #\Newline) content "<br>"))))

(defun import-posts (filepath)
  (let* ((xml (cxml:parse-file filepath (cxml-dom:make-dom-builder)))
         (posts (dom:get-elements-by-tag-name xml "item")))
    (load-config)
    (ensure-directories-exist (repo *config*))
    (loop for post across posts do (import-post post))))
