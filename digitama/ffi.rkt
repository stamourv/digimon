#lang at-exp racket

(provide (all-defined-out))
(provide ctype-basetype ctype-c->scheme ctype-scheme->c)

(provide (all-from-out ffi/unsafe))
(provide (all-from-out ffi/unsafe/define))
(provide (all-from-out ffi/unsafe/alloc))

(require (for-syntax syntax/parse))
(require (for-syntax racket/syntax))
(require (for-syntax racket/path))
(require (for-syntax racket/match))
(require (for-syntax racket/sequence))

(require ffi/unsafe)
(require ffi/unsafe/define)
(require ffi/unsafe/alloc)

(require (only-in '#%foreign ctype-basetype ctype-c->scheme ctype-scheme->c))

(define-syntax (digimon-ffi-lib stx)
  (syntax-parse stx #:literals []
    [(_ libname (~optional (~seq #:global? ?:expr) #:defaults ([? #'#true])) (~optional (~seq #:on-fail on-fail:expr) #:defaults ([on-fail #'#false])))
     #'(ffi-lib #:global? ? #:fail on-fail
                (build-path (path-only (resolved-module-path-name (variable-reference->resolved-module-path (#%variable-reference))))
                            "compiled" "native" (system-library-subpath #false) libname))]))

(define-syntax (module-prefab:cstruct/no-auto-update stx)
  (syntax-case stx []
    [(_ src.c) #| TODO: to see if we still have to provide all cstruct ids |#
     (with-syntax ([mod.c (format-id #'src.c "prefab:~a" (path->string (file-name-from-path (syntax->datum #'src.c))))]
                   [([id id/bzero &id/bzero *id &id _!id ([field-id type-expr Type defvalue] ...) !id->list list->!id !id? id* id_t*] ...)
                    (map (lambda [src]
                           (define cexp (regexp-replaces src '([#px"ffi_prefab_" ""] [#px"\\{" " (("] [#px";\\s+(?!\\})" ") ("] [#px";\\s+\\}" ")) "])))
                           (define cstruct (sequence->list #| (force in-port) |# (in-port read (open-input-bytes cexp))))
                           (define rstruct-id (format "~a"  (sequence-ref cstruct 2))) ; this id should take the first place
                           (define cstruct-id (format "!~a" (sequence-ref cstruct 2))) ; this id should not be used directly
                           (define pointer_t* (format "~a*" (sequence-ref cstruct 4))) ; this id should take the place of _id-pointer
                           (with-syntax ([csid (format-id #'csid "~a" rstruct-id)]
                                         [csid/bzero (format-id #'csid/bzero "~a/bzero" rstruct-id)]
                                         [&csid/bzero (format-id #'&csid/bzero "&~a/bzero" rstruct-id)]
                                         [*csid (format-id #'*csid "*~a" rstruct-id)] ; in C, (*p) means get the value that p points to.
                                         [&csid (format-id #'&csid "&~a" rstruct-id)] ; in C, &v mean get the storage address of v
                                         [_csid (format-id #'_csid "_~a" cstruct-id)]
                                         [csid->list (format-id #'csid->list "~a->list" cstruct-id)]
                                         [list->csid (format-id #'list->csid "list->~a" cstruct-id)]
                                         [csid? (format-id #'csid? "~a?" cstruct-id)]
                                         [csid* (format-id #'csid* "_~a-pointer" cstruct-id)]
                                         [id_t* (format-id #'id_t* "~a" pointer_t*)]
                                         [([field-id _type Type defval] ...)
                                          (for/list ([definition (in-list (sequence-ref cstruct 3))])
                                            (define unsigned? (and (memq 'unsigned definition) #true))
                                            (match (remq* '(signed unsigned int) definition)
                                              [(list 'char field) #`(#,field (if #,unsigned? _ubyte _byte) Byte 0)]
                                              [(list field) #`(#,field (if #,unsigned? _uint _int) (if #,unsigned? Nonnegative-Fixnum Fixnum) 0)]
                                              [(list 'short field) #`(#,field (if #,unsigned? _ushort _short) (if #,unsigned? Index Fixnum) 0)]
                                              [(list 'intptr_t field) #`(#,field _intptr Integer 0)]
                                              [(list 'uintptr_t field) #`(#,field _uintptr Natural 0)]
                                              [(list 'long field) #`(#,field (if #,unsigned? _ulong _long) (if #,unsigned? Natural Integer) 0)]
                                              [(list 'long 'long field) #`(#,field (if #,unsigned? _ullong _llong) (if #,unsigned? Natural Integer) 0)]
                                              [(list 'float field) #`(#,field _float Single-Flonum 0.0)]
                                              [(list 'double field) #`(#,field _double Flonum 0.0)]
                                              [(list 'long 'double field) #`(#,field _longdouble Real 0.0)]
                                              [(list 'intmax_t field) #`(#,field _intmax Integer 0)]
                                              [(list 'uintmax_t field) #`(#,field _uintmax Natural 0)]
                                              [(list 'size_t field) #`(#,field _size Natural 0)]
                                              [(list 'ssize_t field) #`(#,field _ssize Integer 0)]
                                              [(list 'time_t field) #`(#,field _ullong Natural 0)]
                                              [(list 'ptrdiff_t field) #`(#,field _ptrdiff Integer 0)]
                                              [_ (raise-syntax-error 'require-prefab-cstruct (format "unknown ctype in ~a" definition) cstruct)]))])
                             #'[csid csid/bzero &csid/bzero *csid &csid _csid ([field-id _type Type defval] ...) csid->list list->csid csid? csid* id_t*]))
                         (parameterize ([current-directory (or (current-load-relative-directory) (current-directory))])
                           (call-with-input-file* (syntax-e #'src.c)
                             (λ [cin] (regexp-match* #px#"typedef\\s+struct\\s+ffi_prefab_\\w+.+?\\}\\s*\\w+\\s*(?=;)" cin)))))])
       #'(module mod.c racket/base
           (provide (all-defined-out))

           (require racket/struct)
           
           (require ffi/unsafe)

           (define-cstruct _!id ([field-id type-expr] ...)) ...
           (define id_t* id*) ...

           (struct id ([field-id] ...) #:prefab) ...
           (define id/bzero (lambda [] (id defvalue ...))) ...

           (define *id (lambda [p] (apply id (!id->list p)))) ...
           (define &id (lambda [s] (list->!id (struct->list s)))) ...
           (define &id/bzero (lambda [] (&id (id defvalue ...)))) ...
             
           (module* typed/ffi typed/racket
             (provide (all-defined-out))

             (require/typed/provide (submod "..")
                                    [#:opaque id_t* !id?] ...
                                    [#:struct id ([field-id : Type] ...)] ...
                                    [*id (-> id_t* id)] ...
                                    [&id (-> id id_t*)] ...
                                    [id/bzero (-> id)] ...
                                    [&id/bzero (-> id_t*)] ...))))]))

(define cvoid*?
  (lambda [v]
    (and v (cpointer? v))))

(define c-extern
  (lambda [variable ctype]
    (get-ffi-obj variable #false ctype)))

(define c-extern/enum
  ;;; racket->c can map multi names to one value, while c->racket uses the last name
  (lambda [symbols #:map-symbol [symmap string-downcase]]
    (_enum (foldl (lambda [c Es] (list* (string->symbol (symmap (~a c))) '= (get-ffi-obj c #false _ufixint) Es)) null symbols))))

(define c-extern/bitmask
  (lambda [symbols #:map-symbol [symmap string-downcase]]
    (_bitmask (foldl (lambda [c Bs] (list* (string->symbol (symmap (~a c))) '= (get-ffi-obj c #false _uint) Bs)) null symbols))))