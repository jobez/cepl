(in-package :cgl)

;; defun-gpu is at the bottom of this file

(defclass gpu-func-spec ()
  ((name :initarg :name)
   (in-args :initarg :in-args)
   (uniforms :initarg :uniforms)
   (context :initarg :context)
   (body :initarg :body)
   (instancing :initarg :instancing)
   (doc-string :initarg :doc-string)
   (declarations :initarg :declarations)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *gpu-func-specs* (make-hash-table :test #'eq))
  (defvar *dependent-gpu-functions* (make-hash-table :test #'eq)))

(defun get-gpu-func-spec (name) (gethash name *gpu-func-specs*))

(defun %recompile-gpu-functions (name)
  )

(defun %trigger-recompile-for-gpu-func-dependent-on (name)
  (mapcar #'%recompile-gpu-functions (gethash name *dependent-gpu-functions*)))

(defun %make-gpu-func-spec (name in-args uniforms context body instancing
                            doc-string declarations)
  (make-instance 'gpu-func-spec
                 :name name
                 :in-args (mapcar #'listify in-args)
                 :uniforms (mapcar #'listify uniforms)
                 :context context
                 :body body
                 :instancing instancing
                 :doc-string doc-string
                 :declarations declarations))
(defun %serialize-gpu-func-spec (spec)
  (with-gpu-func-spec (spec)
    `(%make-gpu-func-spec ',name ',in-args ',uniforms ',context ',body ',instancing
                          ,doc-string ',declarations)))

(defmacro with-gpu-func-spec ((func-spec) &body body)
  `(with-slots (name in-args uniforms context body instancing
                     doc-string declarations) ,func-spec
     (declare (ignorable name in-args uniforms context body instancing
                         doc-string declarations))
     ,@body))

(defun %subscribe-to-gpu-func (name subscribe-to-name)
  (symbol-macrolet ((func-specs (gethash subscribe-to-name
                                         *dependent-gpu-functions*)))
    (when (and (gethash subscribe-to-name *gpu-func-specs*)
               (not (member name func-specs)))
      (format t "; func ~s subscribed to ~s" name subscribe-to-name)
      (push name func-specs))))

(defun %update-gpu-function-data (spec depends-on)
  (with-slots (name) spec
    (mapcar (fn_ #'%subscribe-to-gpu-func name) depends-on)
    (setf (gethash name *gpu-func-specs*) spec)
    (%trigger-recompile-for-gpu-func-dependent-on name)))

(defun %gpu-func-compiles-in-some-context (spec)
  spec
  t)

(defun %expand-all-macros (spec)
  (with-gpu-func-spec (spec)
    (let ((env (make-instance 'varjo::environment)))
      (varjo::pipe-> (nil nil context body env)
        #'varjo::split-input-into-env
        #'varjo::process-context
        (equal #'varjo::symbol-macroexpand-pass
               #'varjo::macroexpand-pass
               #'varjo::compiler-macroexpand-pass)))))

(defun %find-gpu-funcs-in-source (source &optional locally-defined)
  (unless (atom source)
    (remove-duplicates
     (alexandria:flatten
      (let ((s (first source)))
        (cond
          ;; first element isnt a symbol, keep searching
          ((listp s)
           (append (%find-gpu-funcs-in-source s locally-defined)
                   (mapcar (lambda (x) (%find-gpu-funcs-in-source x locally-defined))
                           (rest source))))
          ;; it's a let so ignore the var name
          ((eq s 'varjo::%glsl-let) (%find-gpu-funcs-in-source (cadadr source)
                                                        locally-defined))
          ;; it's a function so skip to the body and
          ((eq s 'varjo::%make-function)
           (%find-gpu-funcs-in-source (cddr source) locally-defined))
          ;; it's a clone-env-block so there could be function definitions in
          ;; here. check for them and add any names to the locally-defined list
          ((eq s 'varjo::%clone-env-block)

           (let* (;; labels puts %make-function straight after the clone-env
                  (count (length (remove 'varjo::%make-function
                                         (mapcar #'first (rest source))
                                         :test-not #'eq)))
                  (names (mapcar #'second (subseq source 1 (1+ count)))))
             (%find-gpu-funcs-in-source (subseq source (1+ count))
                                 (append names locally-defined))))
          ;; its a symbol, just check it isn't varjo's and if we shouldnt ignore
          ;; it then record it
          ((and (not (equal (package-name (symbol-package s)) "VARJO"))
                (not (member s locally-defined)))
           (cons s (mapcar (lambda (x) (%find-gpu-funcs-in-source x locally-defined))
                           (rest source))))
          ;; nothing to see, keep searching
          (t (mapcar (lambda (x) (%find-gpu-funcs-in-source x locally-defined))
                     (rest source)))))))))

(defun %find-gpu-functions-depended-on (spec)
  (%find-gpu-funcs-in-source (%expand-all-macros spec)))

(defun %make-stand-in-lisp-func (spec depends-on)
  (with-gpu-func-spec (spec)
    (let ((arg-names (mapcar #'first in-args))
          (uniform-names (mapcar #'first uniforms)))
      `(progn
         (eval-when (:compile-toplevel :load-toplevel :execute)
           (%update-gpu-function-data ,(%serialize-gpu-func-spec spec)
                                      ',depends-on))
         (defun ,name (,@arg-names
                       ,@(when uniforms (cons (symb :&uniform) uniform-names) ))
           (declare (ignore ,@arg-names ,@uniform-names))
           (warn "GPU Functions cannot currently be used from the cpu"))))))

(defun %def-gpu-function (name in-args uniforms context body instancing
                          doc-string declarations)
  (let ((spec (%make-gpu-func-spec name in-args uniforms context body
                                   instancing doc-string declarations)))
    (assert (%gpu-func-compiles-in-some-context spec))
    (let ((depends-on (%find-gpu-functions-depended-on spec)))
      (%make-stand-in-lisp-func spec depends-on))))

;;--------------------------------------------------

(defmacro defun-gpu (name args &body body)
  (let ((doc-string (when (stringp (first body)) (pop body)))
        (declarations (when (eq (caar body) 'declare) (pop body))))
    (assoc-bind ((in-args nil) (uniforms :&uniform) (context :&context)
                 (instancing :&instancing))
         (lambda-list-split '(:&uniform :&context :&instancing) args)
      (%def-gpu-function name in-args uniforms context body instancing
                         doc-string declarations))))

(defun undefine-gpu-function (name)
  (labels ((%remove-gpu-function-from-dependancy-table (func-name dependencies)
             (when (member name dependencies)
               (setf (gethash func-name *dependent-gpu-functions*)
                     (remove name dependencies)))))
    (maphash #'%remove-gpu-function-from-dependancy-table
             *dependent-gpu-functions*)
    (remhash name *gpu-func-specs*)
    (remhash name *dependent-gpu-functions*))
  nil)

;;--------------------------------------------------

(defun extract-args-from-gpu-functions (function-names)
  (let ((specs (mapcar #'get-gpu-func-spec function-names)))
    (assert (every #'identity specs))
    (aggregate-args-from-specs specs)))

(defun aggregate-args-from-specs (specs &optional (args-accum t) uniforms-accum)
  (if specs
      (let ((spec (first specs)))
        (with-gpu-func-spec (spec)
          (aggregate-args-from-specs
           (rest specs)
           (if (eql t args-accum) in-args args-accum)
           (aggregate-uniforms uniforms uniforms-accum))))
      `(,args-accum &uniform ,@uniforms-accum)))

(defun aggregate-uniforms (from into)
  (if from
      (let ((u (first from)))
        (cond ((not (find (first u) into :test #'equal :key #'first))
               (aggregate-uniforms (rest from) (cons u into)))
              ((find u into :test #'equal)
               (aggregate-uniforms (rest from) into))
              (t (error "Uniforms for the functions are incompatible: ~a ~a"
                        u into))))
      into))

(defmacro with-processed-func-specs ((stages) &body body)
  `(let ((args (extract-args-from-gpu-functions ,stages)))
     (utils:assoc-bind ((in-args nil) (unexpanded-uniforms :&uniform)
                        (context :&context) (instancing :&instancing))
         (utils:lambda-list-split '(&uniform &context &instancing) args)
       ,@body)))
