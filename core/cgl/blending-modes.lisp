;; This software is Copyright (c) 2012 Chris Bagley
;; (techsnuffle<at>gmail<dot>com)
;; Chris Bagley grants you the rights to
;; distribute and use this software as governed
;; by the terms of the Lisp Lesser GNU Public License
;; (http://opensource.franz.com/preamble.html),
;; known as the LLGPL.
;;
(in-package :cgl)

;; Most of the code that uses blend modes will be in other files
;; as it is most needed in map-g and fbos

;; (%gl:blend-func-separate-i draw-buffer-id src-rgb dst-rgb src-alpha dst-alpha)

;; draw-buffer-id
;;   For glBlendFuncSeparatei, specifies the index of the draw buffer for which
;;   to set the blend functions.
;; srcRGB
;;   Specifies how the red, green, and blue blending factors are computed.
;;   The initial value is GL_ONE.
;; dstRGB
;;   Specifies how the red, green, and blue destination blending factors are
;;   computed. The initial value is GL_ZERO.
;; srcAlpha
;;   Specified how the alpha source blending factor is computed. The initial
;;   value is GL_ONE.
;; dstAlpha
;;   Specified how the alpha destination blending factor is computed. The
;;   initial value is GL_ZERO.

;; Despite the apparent precision of the above equations, blending
;; arithmetic is not exactly specified, because blending operates with
;; imprecise integer color values. However, a blend factor that should be
;; equal to 1 is guaranteed not to modify its multiplicand, and a blend
;; factor equal to 0 reduces its multiplicand to 0. For example, when
;; srcRGB​ is GL_SRC_ALPHA​, dstRGB​ is GL_ONE_MINUS_SRC_ALPHA​, and As0 is
;; equal to 1, the equations reduce to simple replacement:

(defvar *blend-color* (v! 0 0 0 0))

(defun blend-func-namep (keyword)
  (not (null (member keyword '(:zero
                               :one
                               :src-color
                               :one-minus-src-color
                               :dst-color
                               :one-minus-dst-color
                               :src-alpha
                               :one-minus-src-alpha
                               :dst-alpha
                               :one-minus-dst-alpha
                               :constant-color
                               :one-minus-constant-color
                               :constant-alpha
                               :one-minus-constant-alpha
                               :src-alpha-saturate
                               :src1-color
                               :one-minus-src1-color
                               :src1-alpha
                               :one-minus-src1-alpha)))))


;; We have another case to deal with. Per buffer blending params
;; is a >v4.0 feature, before that we could only enable for disable
;; blending per buffer.
;; Hmm, we need a flag for this in the attachment
;; see fbo.lisp's #'replace-attachment-array for the catch logic
;; hmm we need to draw down the permutations

;;- - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;; - can enable or disable blend per attachment
;; - >v4 can set params per attachment

;; default blend disable
;; if enabled, default param-override = nil

;; blend disabled - nothing to see here :)
;; blend enabled, no override - just call (gl:enable :blend *)
;; blend enabled, override - only valid >v4, (gl:enable :blend *) and then set
;;- - - - - - - - - - - - - - - - - - - - - - - - - - - - -

;; {TODO} Huge performance costs will be made here, unneccesary enable/disable
;;        all over the place. However will be VERY easy to fix with state-cache
;;        Do it.
(defmacro %with-blending (fbo pattern &body body)
  (cond
    ((null pattern) (error "invalid blending pattern"))
    ((eq pattern t)
     `(progn
        ;; dont know which attachments from pattern so
        ;; use attachment data
        (if (per-attachment-blending-available-p)
            (%loop-setting-attachment-blend-params ,fbo)
            (%loop-setting-shared-blending ,fbo))
        ,@body))
    (t
     `(progn
        ;; use pattern to pick attachments from fbo
        ,(%gen-attachment-blend pattern fbo)
        ,@body))))

(defun %gen-attachment-blend (attachments fbo)
  (let ((a-syms (loop for a in attachments collect (gensym "attachment")))
        (override-syms (loop for a in attachments collect (gensym "override"))))
    `(let* ,(loop :for a :in attachments :for s :in a-syms
               :for o :in override-syms :append
               `((,s (%attachment ,fbo ,a))
                 (,o (%attachment-override-blending ,s))))
       (unless (and ,@override-syms) (%blend-fbo ,fbo))
       (if (per-attachment-blending-available-p)
           (progn
             ,@(loop :for a :in a-syms :for i :from 0 :append
                  `((%blend ,a ,i)
                    (if (%attachment-override-blending ,a)
                        (%blend-attachment-i ,a ,i)
                        (%blend-fbo-i ,fbo ,i)))))
           (progn
             ,@(loop :for a :in a-syms :for i :from 0 :collect
                  `(%blend ,a ,i)))))))

(defun %loop-setting-shared-blending (fbo)
  (%blend-fbo fbo)
  (loop :for a :across (%fbo-attachment-color fbo) :for i :from 0 :do
     (%blend a i)))

(defun %loop-setting-attachment-blend-params (fbo)
  (loop :for a :across (%fbo-attachment-color fbo) :for i :from 0 :do
     (if (blending a)
         (progn
           (%gl:enable-i :blend i)
           (if (%attachment-override-blending a)
               (%blend-attachment-i a i)
               (%blend-fbo-i fbo i)))
         (%gl:disable-i :blend i))))

(defun %blend (attachment i)
  (if (blending attachment)
      (%gl:enable-i :blend i)
      (%gl:disable-i :blend i)))

(defun %blend-fbo (fbo)
  (%gl:blend-equation-separate (%fbo-mode-rgb fbo) (%fbo-mode-alpha fbo))
  (%gl:blend-func-separate (%fbo-source-rgb fbo)
                           (%fbo-source-alpha fbo)
                           (%fbo-destination-rgb fbo)
                           (%fbo-destination-alpha fbo)))

(defun %blend-fbo-i (fbo i)
  (%gl:blend-equation-separate-i i (%fbo-mode-rgb fbo) (%fbo-mode-alpha fbo))
  (%gl:blend-func-separate-i
   i (%fbo-source-rgb fbo) (%fbo-source-alpha fbo)
   (%fbo-destination-rgb fbo) (%fbo-destination-alpha fbo)))

(defun %blend-attachment-i (attachment i)
  (%gl:blend-equation-separate-i
   i (%attachment-mode-rgb attachment) (%attachment-mode-alpha attachment))
  (%gl:blend-func-separate-i
   i (%attachment-source-rgb attachment)
   (%attachment-source-alpha attachment)
   (%attachment-destination-rgb attachment)
   (%attachment-destination-alpha attachment)))

;; functions below were written to help me understand the blending process
;; they are not something to use in attachments. I'm not sure how to expose
;; these (or if I should). I like the idea of cpu side debugging using this
;; but in issolation it doesnt really mean much. Probably only makes sense in
;; a software renderer.

(defun zero
    (source destination &key (target-rgb t) (blend-color *blend-color*))
  (declare (ignore source destination blend-color))
  (if target-rgb
      (v! 0 0 0)
      0))

(defun one
    (source destination &key (target-rgb t) (blend-color *blend-color*))
  (declare (ignore source destination blend-color))
  (if target-rgb
      (v! 1 1 1)
      1))

(defun src-color
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:s~ source :xyz))
      (* (v:w (if target-source source destination))
         (v:w source))))

(defun one-minus-src-color
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:- (v! 1 1 1) (v:s~ source :xyz)))
      (* (v:w (if target-source source destination))
         (- 1 (v:w source)))))

(defun dst-color
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:s~ destination :xyz))
      (* (v:w (if target-source source destination))
         (v:w destination))))

(defun one-minus-dst-color
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:- (v! 1 1 1) (v:s~ destination :xyz)))
      (* (v:w (if target-source source destination))
         (- 1 (v:w destination)))))

(defun src-alpha
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v! (v:w source) (v:w source) (v:w source)))
      (* (v:w (if target-source source destination))
         (v:w source))))

(defun one-minus-src-alpha
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:- (v! 1 1 1) (v! (v:w source) (v:w source) (v:w source))))
      (* (v:w (if target-source source destination))
         (- 1 (v:w source)))))

(defun dst-alpha
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v! (v:w destination) (v:w destination) (v:w destination)))
      (* (v:w (if target-source source destination))
         (v:w destination))))

(defun one-minus-dst-alpha
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:- (v! 1 1 1) (v! (v:w destination) (v:w destination) (v:w destination))))
      (* (v:w (if target-source source destination))
         (v:w destination))))

(defun constant-color
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:s~ blend-color :xyz))
      (* (v:w (if target-source source destination))
         (v:w blend-color))))

(defun one-minus-constant-color
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:- (v! 1 1 1) (v:s~ blend-color :xyz)))
      (* (v:w (if target-source source destination))
         (- 1 (v:w blend-color)))))

(defun constant-alpha
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore ))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v! (v:w blend-color) (v:w blend-color) (v:w blend-color)))
      (* (v:w (if target-source source destination))
         (v:w blend-color))))

(defun one-minus-constant-alpha
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:- (v! 1 1 1) (v! (v:w blend-color) (v:w blend-color) (v:w blend-color))))
      (* (v:w (if target-source source destination))
         (- 1 (v:w blend-color)))))

;; Destination color multiplied by the minimum of the source and (1 – destination)
(defun src-alpha-saturate
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*))
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (let ((factor (min (v:w source) (- 1 (v:w destination)))))
             (v! factor factor factor)))
      (* (v:w (if target-source source destination))
         1)))

(defun src1-color
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*) source-2)
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:s~ source-2 :xyz))
      (* (v:w (if target-source source destination))
         (v:w source-2))))

(defun one-minus-src1-color
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*) source-2)
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:- (v! 1 1 1) (v:s~ source-2 :xyz)))
      (* (v:w (if target-source source destination))
         (- 1 (v:w source-2)))))

(defun src1-alpha
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*) source-2)
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v! (v:w source-2) (v:w source-2) (v:w source-2)))
      (* (v:w (if target-source source destination))
         (v:w source-2))))

(defun one-minus-src1-alpha
    (source destination &key (target-rgb t) (target-source t)
                          (blend-color *blend-color*) source-2)
  (declare (ignore blend-color))
  (if target-rgb
      (v:* (v:s~ (if target-source source destination) :xyz)
           (v:- (v! 1 1 1) (v! (v:w source-2) (v:w source-2) (v:w source-2))))
      (* (v:w (if target-source source destination))
         (- 1 (v:w source-2)))))
