;; This is a stack of useful functions not really thought of as
;; tools for writing games specifically, but rather for writing
;; cepl. 
;; Saying that though, any use is wonderful so enjoy.

(in-package :cepl-utils)


(defmacro gdefun (name lambda-list &body body/options)
  (if (or (null body/options) 
          (consp (car body/options))
          (keywordp (car body/options)))
      `(defgeneric ,name ,lambda-list ,@body/options)
      `(defmethod ,name ,lambda-list ,@body/options)))

(defun listify (x) (if (listp x) x (list x)))

(defmacro dbind (lambda-list expressions &body body)
  `(destructuring-bind ,lambda-list ,expressions ,@body))

(defun sn-equal (a b) (equal (symbol-name a) (symbol-name b)))

(defun replace-nth (list n form)
  `(,@(subseq list 0 n) ,form ,@(subseq list (1+ n))))

(defun hash-values (hash-table)
  (loop for i being the hash-values of hash-table collect i))

(defun hash-keys (hash-table)
  (loop for i being the hash-keys of hash-table collect i))

(defun intersperse (symb sequence)
  (rest (mapcan #'(lambda (x) (list symb x)) sequence)))

;; This will be pretty inefficient, but shoudl be fine for code trees
(defun walk-replace (to-replace replace-with form 
		     &key (test #'eql))
  "This walks a list tree ('form') replacing all occurences of 
   'to-replace' with 'replace-with'. This is pretty inefficent
   but will be fine for macros."
  (cond ((null form) nil)
	((atom form) (if (funcall test form to-replace)
			 replace-with
			 form))
	(t (cons (walk-replace to-replace 
			       replace-with 
			       (car form)
			       :test test) 
		 (walk-replace to-replace 
			       replace-with 
			       (cdr form)
			       :test test)))))

(defun file-to-string (path)
  "Sucks up an entire file from PATH into a freshly-allocated 
   string, returning two values: the string and the number of 
   bytes read."
  (with-open-file (s path)
    (let* ((len (file-length s))
           (data (make-string len)))
      (values data (read-sequence data s)))))

(defun flatten (x)
  "Walks a list tree and flattens it (returns a 1d list 
   containing all the elements from the tree)"
  (labels ((rec (x acc)
             (cond ((null x) acc)
                   ((atom x) (cons x acc))
                   (t (rec (car x)
                           (rec (cdr x) acc))))))
    (rec x nil)))

;; [TODO] damn this is slow
(defun find-in-tree (item tree &key (test #'eql))
  ""
  (labels ((rec (x)
             (cond ((null x) nil)
                   ((atom x) (funcall test x item))
                   (t (or (rec (car x)) (rec (cdr x)))))))
    (rec tree)))


(defun mkstr (&rest args)
  "Takes a list of strings or symbols and returns one string
   of them concatenated together. For example:
    CEPL-EXAMPLES> (cepl-utils:mkstr 'jam 'ham')
     'JAMHAM'
    CEPL-EXAMPLES> (cepl-utils:mkstr 'jam' 'ham')
     'jamham'"
  (with-output-to-string (s)
    (dolist (a args) (princ a s))))

(defun symb (&rest args)
  "This takes a list of symbols (or strings) and outputs one 
   symbol.
   If the input is symbol/s then the output is a regular symbol
   If the input is string/s, then the output is
   a |symbol like this|"
  (values (intern (apply #'mkstr args))))

(defun symb-package (package &rest args)
  (values (intern (apply #'cepl-utils:mkstr args) package)))

(defun make-keyword (&rest args)
  "This takes a list of symbols (or strings) and outputs one 
   keyword symbol.
   If the input is symbol/s then the output is a regular keyword
   If the input is string/s, then the output is
   a :|keyword like this|"
  (values (intern (apply #'mkstr args) "KEYWORD")))

(defun kwd (&rest args)
  "This takes a list of symbols (or strings) and outputs one 
   keyword symbol.
   If the input is symbol/s then the output is a regular keyword
   If the input is string/s, then the output is
   a :|keyword like this|"
  (values (intern (apply #'mkstr args) "KEYWORD")))

(defun group (source n)
  "This takes a  flat list and emit a list of lists, each n long
   containing the elements of the original list"
  (if (zerop n) (error "zero length"))
  (labels ((rec (source acc)
	     (let ((rest (nthcdr n source)))
	       (if (consp rest)
		   (rec rest (cons (subseq source 0 n)
				   acc))
		   (nreverse (cons source acc))))))
    (if source 
	(rec source nil) 
	nil)))

(defvar safe-read-from-string-blacklist
  '(#\# #\: #\|))

(let ((rt (copy-readtable nil)))
  (defun safe-reader-error (stream closech)
    (declare (ignore stream closech))
    (error "safe-read-from-string failure"))

  (dolist (c safe-read-from-string-blacklist)
    (set-macro-character
      c #'safe-reader-error nil rt))

  (defun safe-read-from-string (s &optional fail)
    (if (stringp s)
      (let ((*readtable* rt) *read-eval*)
        (handler-bind
          ((error (lambda (condition)
                    (declare (ignore condition))
                    (return-from
                      safe-read-from-string fail))))
          (read-from-string s)))
      fail)))

(defun sub-at-index (seq index new-val)
  (append (subseq seq 0 index)
	  (list new-val)
	  (subseq seq (1+ index))))

;;; The following util was taken from SBCL's
;;; src/code/*-extensions.lisp

(defun symbolicate-package (package &rest things)
  "Concatenate together the names of some strings and symbols,
producing a symbol in the current package."
  (let* ((length (reduce #'+ things
                         :key (lambda (x) (length (string x)))))
         (name (make-array length :element-type 'character)))
    (let ((index 0))
      (dolist (thing things (values (intern name package)))
        (let* ((x (string thing))
               (len (length x)))
          (replace name x :start1 index)
          (incf index len))))))


(defun lispify-name (name)
  "take a string and changes it to uppercase and replaces
   all underscores _ with minus symbols -"
  (let ((name (if (symbolp name)
                  (mkstr name)
                  name)))
    (string-upcase (substitute #\- #\_ name))))

(defun symbol-name-equal (a b)
  (and (symbolp a) (symbolp b) (equal (symbol-name a) (symbol-name b))))

(defun range (x &optional y z u v)
  (let ((step (or (and (eq y :step) z)
                  (and (eq z :step) u)
                  (and (eq u :step) v)
                  1)))
    (labels ((basic (start end) (loop :for i :from start :below end
                                   :by step :collect i))
             (basic-down (start end) (loop :for i :from start :above end
                                        :by step :collect i))
             (fun (start end fun) (loop :for i :from start :below end
                                     :by step :collect (funcall fun i)))
             (fun-down (start end fun) (loop :for i :from start :above end
                                          :by step :collect (funcall fun i))))
      (typecase y
        ((or symbol null) (if (> x 0) (basic 0 x) (basic-down 0 x)))
        (number (if (or (null z) (keywordp z))
                    (if (> y x) (basic x y) (basic-down x y))
                    (if (> y x) (fun x y z) (fun-down x y z))))
        (function (if (> x 0) (fun 0 x y) (fun-down 0 x y)))))))

(defun rangei (x &optional y z u v)
  (let ((step (or (and (eq y :step) z)
                  (and (eq z :step) u)
                  (and (eq u :step) v)
                  1)))
    (labels ((basic (start end) (loop :for i :from start :upto end
                                   :by step :collect i))
             (basic-down (start end) (loop :for i :from start :downto end
                                        :by step :collect i))
             (fun (start end fun) (loop :for i :from start :upto end
                                     :by step :collect (funcall fun i)))
             (fun-down (start end fun) (loop :for i :from start :downto end
                                          :by step :collect (funcall fun i))))
      (typecase y
        ((or symbol null) (if (> x 0) (basic 0 x) (basic-down 0 x)))
        (number (if (or (null z) (keywordp z))
                    (if (> y x) (basic x y) (basic-down x y))
                    (if (> y x) (fun x y z) (fun-down x y z))))
        (function (if (> x 0) (fun 0 x y) (fun-down 0 x y)))))))

(defun arange (x &optional y z u v)  
  (let ((step (or (and (eq y :step) z)
                  (and (eq z :step) u)
                  (and (eq u :step) v)
                  1)))
    (labels ((basic (start end) (loop :for i :from start :below end
                                   :by step :collect i))
             (basic-down (start end) (loop :for i :from start :above end
                                        :by step :collect i))
             (fun (start end fun) (loop :for i :from start :below end
                                     :by step :collect (funcall fun i)))
             (fun-down (start end fun) (loop :for i :from start :above end
                                          :by step :collect (funcall fun i))))
      (typecase y
        ((or symbol null) 
         (make-array x :initial-contents
                     (if (> x 0) (basic 0 x) (basic-down 0 x))))
        (number (make-array (abs (- y x))
                            :initial-contents
                            (if (or (null z) (keywordp z))
                                (if (> y x) (basic x y) (basic-down x y))
                                (if (> y x) (fun x y z) (fun-down x y z)))))
        (function (make-array x :initial-contents
                              (if (> x 0) (fun 0 x y) (fun-down 0 x y))))))))

(defun arangei (x &optional y z u v)  
  (let ((step (or (and (eq y :step) z)
                  (and (eq z :step) u)
                  (and (eq u :step) v)
                  1)))
    (labels ((basic (start end) (loop :for i :from start :upto end
                                   :by step :collect i))
             (basic-down (start end) (loop :for i :from start :downto end
                                        :by step :collect i))
             (fun (start end fun) (loop :for i :from start :upto end
                                     :by step :collect (funcall fun i)))
             (fun-down (start end fun) (loop :for i :from start :downto end
                                          :by step :collect (funcall fun i))))
      (typecase y
        ((or symbol null) 
         (make-array (1+ x) :initial-contents
                     (if (> x 0) (basic 0 x) (basic-down 0 x))))
        (number (make-array (1+ (abs (- y x)))
                            :initial-contents
                            (if (or (null z) (keywordp z))
                                (if (> y x) (basic x y) (basic-down x y))
                                (if (> y x) (fun x y z) (fun-down x y z)))))
        (function (make-array (1+ x) :initial-contents
                              (if (> x 0) (fun 0 x y) (fun-down 0 x y))))))))






(define-compiler-macro mapcat (function &rest lists)
  `(apply #'concatenate 'list (mapcar ,function ,@lists)))

(defun mapcat (function &rest lists)
  (apply #'concatenate 'list (apply #'mapcar function lists)))
