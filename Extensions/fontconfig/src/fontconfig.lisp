(in-package :mcclim-fontconfig)

(defvar *config* nil)

(defun find-config ()
  (unless *config*
    (init-fontconfig))
  *config*)

(defclass fontconfig-memory-mixin ()
  ((ptr :reader fontconfig-memory-mixin/ptr
        :initarg :ptr
        :documentation "The wrapped pointer"))
  (:documentation "Mixin class for types that wraps a pointer that
needs to be released after the instance is no longer referenced. The
actual registration of the object is handled by the subclass."))

(defclass pattern (fontconfig-memory-mixin)
  ()
  (:documentation "Wrapper class for pattern objects"))

(defmethod initialize-instance :after ((obj pattern) &key)
  (let ((ptr (fontconfig-memory-mixin/ptr obj)))
    (trivial-garbage:finalize obj (lambda ()
                                    (fc-pattern-destroy ptr)))))

(defun error-if-fail (result)
  (when (zerop result)
    (error 'fontconfig-error)))

(defun init-fontconfig ()
  (unless *config*
    (setq *config* (fc-init-load-config-and-fonts)))
  nil)

(defun get-version ()
  (fc-get-version))

(defun init-reinitialize ()
  (error-if-fail (fc-init-reinitialize)))

(defun init-bring-up-to-date ()
  (error-if-fail (fc-init-bring-up-to-date)))

(defun add-string-value-to-pattern (pattern key value)
  (cffi:with-foreign-strings ((s value :encoding :utf-8))
    (error-if-fail (fc-pattern-add-string pattern key s))))

(defun add-value-to-pattern (pattern key value)
  (check-type key string)
  (etypecase value
    (string (add-string-value-to-pattern pattern key value))
    (integer (error-if-fail (fc-pattern-add-integer pattern key value)))
    (keyword (ecase value
               (:true (fc-pattern-add-bool pattern key 1))
               (:false (fc-pattern-add-bool pattern key 0))))))

(defun make-pattern (values)
  (let ((pattern (fc-pattern-create)))
    (loop
      for (key . value) in values
      do (add-value-to-pattern pattern key value))
    (make-instance 'pattern :ptr pattern)))

(defun name-parse (name)
  (cffi:with-foreign-string (s name :encoding :utf-8)
    (let ((result (fc-name-parse s)))
      (make-instance 'pattern :ptr result))))

(defun match (pattern)
  (check-type pattern pattern)
  (let* ((p (fontconfig-memory-mixin/ptr pattern)))
    (fc-default-substitute p)
    (cffi:with-foreign-objects ((result 'fc-result))
      (let* ((matched (fc-font-match (find-config) p result))
             (result-obj (cffi:mem-ref result 'fc-result)))
        (let ((matched-obj (cond ((cffi:null-pointer-p matched)
                                  nil)
                                 (t
                                  (make-instance 'pattern :ptr matched)))))
          (unless (eq result-obj :fc-result-match)
            (error 'fontconfig-match-error :status result-obj))
          matched-obj)))))

(defun value->lisp (value)
  (labels ((getslot (name)
             (cffi:foreign-slot-value value '(:struct fc-value) name)))
    (ecase (cffi:foreign-slot-value value '(:struct fc-value) 'type)
      (:fc-type-unknown :type-unknown)
      (:fc-type-void nil)
      (:fc-type-integer (getslot 'value-int))
      (:fc-type-double (getslot 'value-double))
      (:fc-type-string (values (cffi:foreign-string-to-lisp (getslot 'value-fchar8) :encoding :utf-8)))
      (:fc-type-bool (if (zerop (getslot 'value-bool)) nil t))
      (:fc-type-matrix :matrix-not-implemented)
      (:fc-type-char-set :char-set-not-implemented)
      (:fc-type-ft-face :ft-face-not-implemented)
      (:fc-type-lang-set :lang-set-not-implemented)
      (:fc-type-range :range-not-implemented))))

(defun pattern-get-internal (p object index)
  (cffi:with-foreign-objects ((value '(:struct fc-value)))
    (let ((result (fc-pattern-get p object index value)))
      (case result
        (:fc-result-match (values (value->lisp value) :match))
        (:fc-result-no-match (values nil :no-match))
        (:fc-result-no-id (values nil :no-id))
        (t (error 'fontconfig-match-error :status result))))))

(defun pattern-get (pattern object index)
  (check-type pattern pattern)
  (check-type object string)
  (check-type index integer)
  (let ((p (fontconfig-memory-mixin/ptr pattern)))
    (pattern-get-internal p object index)))

(defun config-home ()
  (let ((result (fc-config-home)))
    (values (cffi:foreign-string-to-lisp result))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Simple interface
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar *propery-names* '((:family . "family")
                          (:familylang . "familylang")
                          (:style . "style")
                          (:stylelang . "stylelang")
                          (:fullname . "fullname")
                          (:fullnamelang . "fullnamelang")
                          (:slant . "slant")
                          (:weight . "weight")
                          (:size . "size")
                          (:width . "width")
                          (:aspect . "aspect")
                          (:pixelsize . "pixelsize")
                          (:spacing . "spacing")
                          (:foundry . "foundry")
                          (:antialias . "antialias")
                          (:hinting . "hinting")
                          (:hintstyle . "hintstyle")
                          (:verticallayout . "verticallayout")
                          (:autohint . "autohint")
                          (:globaladvance . "globaladvance")
                          (:file . "file")
                          (:index . "index")
                          (:ftface . "ftface")
                          (:rasterizer . "rasterizer")
                          (:outline . "outline")
                          (:scalable . "scalable")
                          (:scale . "scale")
                          (:symbol . "symbol")
                          (:color . "color")
                          (:dpi . "dpi")
                          (:rgba . "rgba")
                          (:lcdfilter . "lcdfilter")
                          (:minspace . "minspace")
                          (:charset . "charset")
                          (:lang . "lang")
                          (:fontversion . "fontversion")
                          (:capability . "capability")
                          (:fontformat . "fontformat")
                          (:embolden . "embolden")
                          (:embeddedbitmap . "embeddedbitmap")
                          (:decorative . "decorative")
                          (:fontfeatures . "fontfeatures")
                          (:namelang . "namelang")
                          (:prgname . "prgname")
                          (:hash . "hash")
                          (:postscriptname . "postscriptname")))

(defmacro with-new-pattern ((sym) &body body)
  (alexandria:with-gensyms (pattern)
    `(let ((,pattern (fc-pattern-create)))
       (unwind-protect
            (let ((,sym ,pattern))
              ,@body)
         (fc-pattern-destroy ,pattern)))))

(defun pattern-to-lisp (pattern fields)
  (loop
    for field in fields
    for v = (assoc field *propery-names*)
    when v
      collect (cons field (pattern-get-internal pattern (cdr v) 0))))

(defun fill-pattern-from-values (pattern values)
  (when values
    (loop
      for (key . value) in values
      do (add-value-to-pattern pattern (prop-to-name key) value))))

(defun match-font (values fields)
  (with-new-pattern (pattern)
    (fill-pattern-from-values pattern values)
    (fc-default-substitute pattern)
    (cffi:with-foreign-objects ((result 'fc-result))
      (let* ((matched (fc-font-match (find-config) pattern result))
             (result-obj (cffi:mem-ref result 'fc-result)))
        (unwind-protect
             (progn
               (unless (eq result-obj :fc-result-match)
                 (error 'fontconfig-match-error :status result-obj))
               (pattern-to-lisp matched fields))
          (unless (cffi:null-pointer-p matched)
            (fc-pattern-destroy matched)))))))

(defmacro with-object-set ((sym objects) &body body)
  (alexandria:once-only (objects)
    (alexandria:with-gensyms (object-set obj)
      `(let ((,object-set (fc-object-set-create)))
         (unwind-protect
              (progn
                (loop
                  for ,obj in ,objects
                  do (fc-object-set-add ,object-set ,obj))
                (let ((,sym ,object-set))
                  ,@body))
           (fc-object-set-destroy ,object-set))))))

(defun prop-to-name (prop)
  (let ((d (assoc prop *propery-names*)))
    (unless d
      (error "Unknown property: ~s" prop))
    (cdr d)))

(defun font-list (pattern fields)
  (with-object-set (object-set (mapcar #'prop-to-name fields))
    (with-new-pattern (p)
      (fill-pattern-from-values p pattern)
      (let ((f (fc-font-list (find-config) p object-set)))
        (loop
          with n = (cffi:foreign-slot-value f '(:struct fc-font-set) 'nfont)
          with fonts-ptr = (cffi:foreign-slot-value f '(:struct fc-font-set) 'fonts)
          for i from 0 below n
          for font = (cffi:mem-aref fonts-ptr :pointer i)
          collect (pattern-to-lisp font fields))))))
