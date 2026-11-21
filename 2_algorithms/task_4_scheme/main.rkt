
#lang racket

;; Чтение деревьев из файла
(define (read-trees filename)
  (call-with-input-file
   filename
   (lambda (in)
     (let loop ([trees '()])
       (define t (read in))
       (if (eof-object? t)
           (reverse trees)
           (loop (cons t trees)))))))

;; Проверка корректности дерева
(define (valid-tree? t)
  (and (list? t)
       (pair? t)
       (symbol? (car t))
       (andmap valid-tree? (cdr t))))

;; Подсчет узлов в дереве
(define (count-nodes t)
  (+ 1
     (for/sum ([child (in-list (cdr t))])
       (count-nodes child))))

;; Подсчет узлов в лесу
(define (count-forest forest)
  (for/sum ([tree (in-list forest)])
    (count-nodes tree)))

(struct dp-result (distance choice) #:transparent)

;; Таблица мемоизации
(define memo (make-hash))

;; Расстояние между лесами
(define (forest-dist f1 f2)
  (dp-result-distance (forest-result f1 f2)))

;; Получение результата с мемоизацией
(define (forest-result f1 f2)
  (hash-ref!
   memo
   (list f1 f2)
   (lambda ()
     (calc-forest-result f1 f2))))

;; Рекурсивное вычисление расстояния
(define (calc-forest-result f1 f2)
  (cond
    [(and (null? f1) (null? f2))
     (dp-result 0 'done)]

    [(null? f1)
     (dp-result (count-forest f2) 'insert-all)]

    [(null? f2)
     (dp-result (count-forest f1) 'delete-all)]

    [else
     (let* ([t1 (car f1)]
            [t2 (car f2)]
            [rest1 (cdr f1)]
            [rest2 (cdr f2)]
            [lbl1 (car t1)]
            [lbl2 (car t2)]
            [children1 (cdr t1)]
            [children2 (cdr t2)]
            [relabel-cost (if (equal? lbl1 lbl2) 0 1)]

            [match-cost
             (+ relabel-cost
                (forest-dist children1 children2)
                (forest-dist rest1 rest2))]

            [delete-cost
             (+ 1
                (forest-dist
                 (append children1 rest1)
                 f2))]

            [insert-cost
             (+ 1
                (forest-dist
                 f1
                 (append children2 rest2)))]

            [candidates
             (list (cons match-cost 'match)
                   (cons delete-cost 'delete)
                   (cons insert-cost 'insert))]

            [best
             (for/fold ([best (car candidates)])
                       ([candidate (in-list (cdr candidates))])
               (if (< (car candidate) (car best))
                   candidate
                   best))])

       (dp-result (car best) (cdr best)))]))

;; Вставка дерева: сначала дочерние узлы, затем родитель
(define (insert-tree-ops tree context)
  (append
   (insert-forest-ops
    (cdr tree)
    (format "дочерний лес узла '~a'" (car tree)))
   (list
    (format
     "Вставить узел '~a' в указанный лес (~a), присоединив к нему первые ~a деревьев."
     (car tree)
     context
     (length (cdr tree))))))

;; Вставка нескольких деревьев
(define (insert-forest-ops forest context)
  (for/fold ([ops '()])
            ([tree (in-list (reverse forest))])
    (append ops (insert-tree-ops tree context))))

;; Удаление всех узлов леса
(define (delete-forest-ops forest context)
  (for/fold ([ops '()])
            ([tree (in-list forest)])
    (append
     ops
     (list
      (format
       "Удалить корень дерева с меткой '~a' из указанного леса (~a); его дочерние деревья перемещаются в начало леса."
       (car tree)
       context))
     (delete-forest-ops (cdr tree) context))))

;; Восстановление минимальной последовательности операций
(define (build-ops f1 f2 [context "текущий лес"])
  (define result (forest-result f1 f2))

  (case (dp-result-choice result)

    [(done)
     '()]

    [(insert-all)
     (insert-forest-ops f2 context)]

    [(delete-all)
     (delete-forest-ops f1 context)]

    [(match)
     (let* ([t1 (car f1)]
            [t2 (car f2)]
            [lbl1 (car t1)]
            [lbl2 (car t2)])

       (append
        (if (equal? lbl1 lbl2)
            '()
            (list
             (format
              "Заменить метку корня '~a' на '~a' в указанном лесу (~a)."
              lbl1 lbl2 context)))

        (build-ops
         (cdr t1)
         (cdr t2)
         (format "дочерний лес узла '~a'" lbl1))

        (build-ops (cdr f1) (cdr f2) context)))]

    [(delete)
     (let ([t1 (car f1)])
       (append
        (list
         (format
          "Удалить корень дерева с меткой '~a' из указанного леса (~a); его дочерние деревья переместить в начало леса."
          (car t1)
          context))

        (build-ops
         (append (cdr t1) (cdr f1))
         f2
         context)))]

    [(insert)
     (let* ([t2 (car f2)]
            [children2 (cdr t2)]
            [rest2 (cdr f2)])

       (append
        (build-ops
         f1
         (append children2 rest2)
         context)

        (list
         (format
          "Вставить узел '~a' в указанный лес (~a), присоединив к нему первые ~a деревьев."
          (car t2)
          context
          (length children2)))))]))

;; Вывод операций
(define (print-ops operations)
  (if (null? operations)
      (displayln "Операций не требуется.")
      (for ([op (in-list operations)]
            [i (in-naturals 1)])
        (displayln (format "~a. ~a" i op)))))

;; Главная функция
(define (main)
  (with-handlers
      ([exn:fail:read?
        (lambda (e)
          (displayln
           (format "Ошибка чтения S-выражения: ~a"
                   (exn-message e))))]

       [exn:fail?
        (lambda (e)
          (displayln
           (format "Ошибка: ~a" (exn-message e))))])

    (let ([trees (read-trees "input.txt")])
      (cond
        [(null? trees)
         (displayln "Ошибка: файл input.txt пуст.")]

        [(not (= (length trees) 2))
         (displayln
          "Ошибка: в файле должно быть ровно два S-выражения.")]

        [(not (valid-tree? (car trees)))
         (displayln
          "Ошибка: первое S-выражение имеет неверный формат дерева.")]

        [(not (valid-tree? (cadr trees)))
         (displayln
          "Ошибка: второе S-выражение имеет неверный формат дерева.")]

        [else
         (let ([t1 (car trees)]
               [t2 (cadr trees)])

           (hash-clear! memo)

           (let* ([dist (forest-dist (list t1) (list t2))]
                  [operations
                   (build-ops (list t1) (list t2))])

             (displayln
              (format "Расстояние редактирования: ~a" dist))

             (displayln
              "Одна из минимальных последовательностей операций:")

             (print-ops operations)

             (when (not (= dist (length operations)))
               (displayln
                "Ошибка: количество восстановленных операций не совпадает с расстоянием."))))]))))

(main)
