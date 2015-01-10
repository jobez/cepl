(in-package #:cepl.events.sdl)

;;--------------------------------------------
;; Lisp sdl events

(defclass sdl-event ()
  ((timestamp :initform 0 :initarg :timestamp :reader timestamp
              :type fixnum)))
(defclass will-quit (sdl-event) ())
(defclass window (sdl-event)
  ((action :initarg action :initform nil :reader action
           :type fixnum)
   (vec :initarg :vec :reader vec
        :type (simple-array (single-float 3)))))
(defclass mouse-scroll (sdl-event)
  ((source-id :initform 0 :type fixnum)
   (vec :initarg :vec :reader vec
        :type (simple-array (single-float 3)))))
(defclass mouse-button (sdl-event)
  ((source-id :initarg :source-id :initform 0 :reader id
              :type fixnum)
   (button :initarg :button :initform 0 :reader button
           :type keyword)
   (state :initarg :state :initform 0 :reader state
          :type keyword)
   (clicks :initarg :clicks :initform 0 :reader clicks
           :type fixnum)
   (pos :initarg :pos :reader pos
        :type (simple-array (single-float 3)))))
(defclass mouse-motion (sdl-event)
  ((source-id :initarg :source-id :initform 0 :reader source-id
              :type fixnum)
   (state :initarg :state :initform 0 :reader state
          :type fixnum)
   (pos :initarg :pos :reader pos
        :type (simple-array (single-float 3)))
   (delta :initarg :delta :reader delta
          :type (simple-array (single-float 3)))))
(defclass key (sdl-event)
  ((etype :initarg :etype :reader etype 
          :type keyword)
   (state :initarg state :initform 0  :reader state
          :type fixnum)
   (repeat :initarg repeat :initform 0 :reader repeat
           :type boolean)
   (key :initarg key :initform 0 :reader key
        :type keyword)))


;;--------------------------------------------
;; sdl timestamp conversion

;; {TODO} optimize
(let ((sdl->lisp-time-offset 0))
  (defun set-sdl->lisp-time-offset ()
    (setf sdl->lisp-time-offset (- (get-internal-real-time) (sdl2::get-ticks))))
  (defun sdl->lisp-time (sdl-time)
    (when (= sdl->lisp-time-offset 0)
      (set-sdl->lisp-time-offset))
    (cepl.events:+ sdl-time sdl->lisp-time-offset))
  (defun lisp->sdl-time (lisp-time)
    (when (= sdl->lisp-time-offset 0)
      (set-sdl->lisp-time-offset))
    (- lisp-time sdl->lisp-time-offset)))

;;--------------------------------------------
;; sdl event helpers

(defmacro case-events ((event &key (method :poll) (timeout nil))
                       &body event-handlers)
  (labels ((my-expand-handler (event type params forms)
             (if (listp type)
                 (sdl2::expand-handler event (first type) params forms)
                 (sdl2::expand-handler event type params forms))))
    `(let (,(when (symbolp event) `(,event (sdl2:new-event))))
       (loop :until (= 0  (sdl2:next-event ,event ,method ,timeout)) :do
          (case (sdl2::get-event-type ,event)
            ,@(loop :for (type params . forms) :in event-handlers :collect
                 (my-expand-handler event type params forms) :into results
                 :finally (return (remove nil results)))))
       (sdl2:free-event ,event))))

(defun collect-sdl-events ()
  (let ((results nil))
    (case-events (event)
                 (:quit (:timestamp ts)
                        (cepl.events:push (make-instance 'will-quit :timestamp ts) results))

                 (:windowevent (:timestamp ts :event e :data1 x :data2 y)
                               (cepl.events:push (make-instance 'window
                                                    :timestamp (sdl->lisp-time ts)
                                                    :action e 
                                                    :vec (base-vectors:v! x y))
                                     results))

                 (:mousewheel (:timestamp ts :which id :x x :y y)
                              (cepl.events:push (make-instance 'mouse-scroll
                                                   :timestamp (sdl->lisp-time ts)
                                                   :source-id id :vec (base-vectors:v! x y))
                                    results))

                 ((:mousebuttondown :mousebuttonup) 
                  (:timestamp ts :which id :button b :state s 
                              :clicks c :x x :y y)
                  (cepl.events:push (make-instance 'mouse-button
                                       :timestamp (sdl->lisp-time ts)
                                       :source-id id 
                                       :button (mouse-button-lookup b) 
                                       :state (mouse-button-state-lookup s)
                                       :clicks c 
                                       :pos (base-vectors:v! x y))
                        results))

                 (:mousemotion
                  (:timestamp ts :which id :state s :x x :y y :xrel xrel :yrel yrel)
                  (cepl.events:push (make-instance 'mouse-motion
                                       :timestamp (sdl->lisp-time ts)
                                       :source-id id
                                       :state s
                                       :pos (base-vectors:v! x y)
                                       :delta (base-vectors:v! xrel yrel))
                        results))
                 
                 ((:keydown :keyup)
                  (:type typ :timestamp ts :state s :repeat r :keysym keysym)
                  (cepl.events:push (make-instance 'key 
                                       :timestamp (sdl->lisp-time ts)
                                       :etype (key-type-lookup typ)
                                       :state (key-state-lookup s)
                                       :repeat (= r 0)
                                       :key (sdl-scancode-lookup 
                                             (plus-c:c-ref keysym sdl2-ffi:sdl-keysym :scancode)))
                        results)))
    results))

(defun pump-sdl-events () (cepl.events:push nil |sdl-all-events|))

;;--------------------------------------------
;; sources

(defnode |sdl-all-events| (:var _ :kind expand)
  (declare (ignore _)) 
  (collect-sdl-events))

(defnode |mouse| (:source |sdl-all-events| :var x :kind filter)
  (or (and (typep x 'mouse-scroll) (= (id x) 0))
      (and (typep x 'mouse-button) (= (id x) 0))
      (and (typep x 'mouse-motion) (= (id x) 0))))

(defnode |sdl-sys| (:source |sdl-all-events| :var x :kind filter)
  (typep x 'will-quit))

(defnode |keyboard| (:source |sdl-all-events| :var x :kind filter)
  (typep x 'key))

;;--------------------------------------------
;; scancode lookup

(defun key-type-lookup (num) (aref #(:keydown :keyup) num))
(defun key-state-lookup (num) (aref #(:pressed :released) num))

(defun mouse-button-lookup (num) (aref #(:left :middle :right) num))

(defun mouse-button-state-lookup (num) (aref #(:pressed :released) num))

(defun sdl-scancode-lookup (scancode)
  (aref *sdl-scan-lookup* scancode))

(defparameter *sdl-scan-lookup* 
  #(:unknown nil nil nil :a :b
    :c :d :e :f
    :g :h :i :j
    :k :l :m :n
    :o :p :q :r
    :s :t :u :v
    :w :x :y :z
    :1 :2 :3 :4
    :5 :6 :7 :8
    :9 :0 :return :escape
    :backspace :tab :space
    :minus :equals :leftbracket
    :rightbracket :backslash :nonushash
    :semicolon :apostrophe :grave
    :comma :period :slash
    :capslock :f1 :f2 :f3
    :f4 :f5 :f6 :f7
    :f8 :f9 :f10 :f11
    :f12 :printscreen :scrolllock
    :pause :insert :home
    :pageup :delete :end
    :pagedown :right :left
    :down :up :numlockclear
    :kp_divide :kp_multiply :kp_minus
    :kp_plus :kp_enter :kp_1
    :kp_2 :kp_3 :kp_4 :kp_5
    :kp_6 :kp_7 :kp_8 :kp_9
    :kp_0 :kp_period :nonusbackslash
    :application :power :kp_equals
    :f13 :f14 :f15 :f16
    :f17 :f18 :f19 :f20
    :f21 :f22 :f23 :f24
    :execute :help :menu
    :select :stop :again
    :undo :cut :copy :paste
    :find :mute :volumeup
    :volumedown :lockingcapslock
    :lockingnumlock :lockingscrolllock
    :kp_comma :kp_equalsas400
    :international1 :international2
    :international3 :international4
    :international5 :international6
    :international7 :international8
    :international9 :lang1 :lang2
    :lang3 :lang4 :lang5
    :lang6 :lang7 :lang8
    :lang9 :alterase :sysreq
    :cancel :clear :prior
    :return2 :separator :out
    :oper :clearagain :crsel
    :exsel nil nil nil nil nil nil nil nil nil nil nil
    :kp_00 :kp_000 :thousandsseparator
    :decimalseparator :currencyunit
    :currencysubunit :kp_leftparen
    :kp_rightparen :kp_leftbrace
    :kp_rightbrace :kp_tab :kp_backspace
    :kp_a :kp_b :kp_c :kp_d
    :kp_e :kp_f :kp_xor
    :kp_power :kp_percent :kp_less
    :kp_greater :kp_ampersand
    :kp_dblampersand :kp_verticalbar
    :kp_dblverticalbar :kp_colon :kp_hash
    :kp_space :kp_at :kp_exclam
    :kp_memstore :kp_memrecall
    :kp_memclear :kp_memadd
    :kp_memsubtract :kp_memmultiply
    :kp_memdivide :kp_plusminus :kp_clear
    :kp_clearentry :kp_binary :kp_octal
    :kp_decimal :kp_hexadecimal nil nil
    :lctrl :lshift :lalt
    :lgui :rctrl :rshift
    :ralt :rgui nil nil nil nil nil nil nil nil nil nil
    nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
    :mode :audionext :audioprev
    :audiostop :audioplay :audiomute
    :mediaselect :www :mail
    :calculator :computer :ac_search
    :ac_home :ac_back :ac_forward
    :ac_stop :ac_refresh :ac_bookmarks
    :brightnessdown :brightnessup
    :displayswitch :kbdillumtoggle
    :kbdillumdown :kbdillumup :eject
    :sleep))


;; {TODO} support these events
;; :textediting
;; :textinput

;; :joyaxismotion
;; :joyballmotion
;; :joyhatmotion
;; :joybuttondown
;; :joybuttonup
;; :joydeviceadded
;; :joydeviceremoved

;; :controlleraxismotion
;; :controllerbuttondown
;; :controllerbuttonup
;; :controllerdeviceadded
;; :controllerdeviceremoved
;; :controllerdeviceremapped

;; :fingerdown
;; :fingerup
;; :fingermotion

;; :multigesture

;; :clipboardupdate

;; :dropfile

;; :render-targets-reset

;; :userevent
;; :lastevent

