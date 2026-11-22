
(ns main
  (:require [clojure.string :as str])
  (:import [java.util LinkedHashMap Map]
           [java.math BigInteger BigDecimal]))

;; ============================================================
;; Общие функции
;; ============================================================

(def bare-key-pattern #"[A-Za-z0-9_-]+")

(def number-pattern
  #"^[+-]?(?:0|[1-9](?:_?[0-9])*)(?:\.[0-9](?:_?[0-9])*(?:[eE][+-]?[0-9](?:_?[0-9])*)?|[eE][+-]?[0-9](?:_?[0-9])*)?")

(defn parse-error [line message]
  (throw
    (ex-info
      (str "Строка " line ": " message)
      {:line line})))

(defn skip-ws [^String s start]
  (loop [i start]
    (if (and (< i (.length s))
             (Character/isWhitespace (.charAt s i)))
      (recur (inc i))
      i)))

;; ============================================================
;; Удаление комментариев
;; ============================================================

(defn strip-comment [^String s]
  (loop [i 0
         quote nil
         escaped false]

    (if (>= i (.length s))
      s

      (let [ch (.charAt s i)]
        (cond

          (and (= quote \") escaped)
          (recur (inc i) quote false)

          (and (= quote \") (= ch \\))
          (recur (inc i) quote true)

          (and (nil? quote)
               (or (= ch \") (= ch \')))
          (recur (inc i) ch false)

          (and (some? quote) (= ch quote))
          (recur (inc i) nil false)

          (and (nil? quote) (= ch \#))
          (subs s 0 i)

          :else
          (recur (inc i) quote false))))))

;; ============================================================
;; Поиск знака равенства вне строк
;; ============================================================

(defn find-equals-index [^String s]
  (loop [i 0
         quote nil
         escaped false]

    (if (>= i (.length s))
      -1

      (let [ch (.charAt s i)]
        (cond

          (and (= quote \") escaped)
          (recur (inc i) quote false)

          (and (= quote \") (= ch \\))
          (recur (inc i) quote true)

          (and (nil? quote) (= ch \=))
          i

          (and (nil? quote)
               (or (= ch \") (= ch \')))
          (recur (inc i) ch false)

          (and (some? quote) (= ch quote))
          (recur (inc i) nil false)

          :else
          (recur (inc i) quote false))))))

;; ============================================================
;; Разбор строк в кавычках
;; ============================================================

(defn parse-quoted-string
  [^String s start line quote]

  (loop [i start
         out (StringBuilder.)]

    (when (>= i (.length s))
      (parse-error line "Незакрытая строка"))

    (let [ch (.charAt s i)]

      (cond

        (= ch quote)
        [(.toString out) (inc i)]

        (and (= quote \") (= ch \\))

        (do
          (when (>= (inc i) (.length s))
            (parse-error line "Незавершённая escape-последовательность"))

          (let [escaped-char (.charAt s (inc i))]

            (case (int escaped-char)

              34
              (do
                (.append out (char 34))
                (recur (+ i 2) out))

              92
              (do
                (.append out (char 92))
                (recur (+ i 2) out))

              98
              (do
                (.append out (char 8))
                (recur (+ i 2) out))

              102
              (do
                (.append out (char 12))
                (recur (+ i 2) out))

              110
              (do
                (.append out (char 10))
                (recur (+ i 2) out))

              114
              (do
                (.append out (char 13))
                (recur (+ i 2) out))

              116
              (do
                (.append out (char 9))
                (recur (+ i 2) out))

              117
              (let [hex-end (+ i 6)]

                (when (> hex-end (.length s))
                  (parse-error line "Неполная Unicode-последовательность"))

                (let [hex (subs s (+ i 2) hex-end)]

                  (when-not (re-matches #"[0-9a-fA-F]{4}" hex)
                    (parse-error line "Некорректная Unicode-последовательность"))

                  (.append out (char (Integer/parseInt hex 16)))
                  (recur hex-end out)))

              (parse-error line "Неизвестная escape-последовательность"))))

        (< (int ch) 32)
        (parse-error line "Недопустимый управляющий символ в строке")

        :else
        (do
          (.append out ch)
          (recur (inc i) out))))))

;; ============================================================
;; Рекурсивный разбор значений
;; ============================================================

(declare parse-value)

(defn parse-array [^String s start line]

  (loop [i (skip-ws s start)
         values []]

    (when (>= i (.length s))
      (parse-error line "Незакрытый массив"))

    (let [ch (.charAt s i)]

      (cond

        (= ch \])
        [values (inc i)]

        :else

        (let [[value next-index] (parse-value s i line)
              next-index (skip-ws s next-index)
              values (conj values value)]

          (when (>= next-index (.length s))
            (parse-error line "Незакрытый массив"))

          (case (.charAt s next-index)

            \,
            (let [after-comma
                  (skip-ws s (inc next-index))]

              (if (and (< after-comma (.length s))
                       (= (.charAt s after-comma) \]))

                [values (inc after-comma)]

                (recur after-comma values)))

            \]
            [values (inc next-index)]

            (parse-error line
              "Ожидалась запятая или закрывающая скобка массива")))))))

(defn parse-value [^String s start line]

  (let [i (skip-ws s start)]

    (when (>= i (.length s))
      (parse-error line "Отсутствует значение"))

    (let [ch (.charAt s i)]

      (cond

        (= ch \")
        (parse-quoted-string s (inc i) line \")

        (= ch \')
        (parse-quoted-string s (inc i) line \')

        (= ch \[)
        (parse-array s (inc i) line)

        (.startsWith s "true" i)
        [true (+ i 4)]

        (.startsWith s "false" i)
        [false (+ i 5)]

        :else

        (let [token (re-find number-pattern (subs s i))]

          (if (nil? token)

            (parse-error line
              (str "Неизвестный тип значения: " (subs s i)))

            (let [normalized
                  (str/replace token "_" "")

                  floating?
                  (boolean (re-find #"[.eE]" normalized))

                  value
                  (if floating?
                    (BigDecimal. normalized)
                    (BigInteger. normalized))]

              [value (+ i (count token))])))))))

;; ============================================================
;; Разбор ключей
;; ============================================================

(defn parse-key [raw line]

  (let [key-text (str/trim raw)]

    (when (empty? key-text)
      (parse-error line "Пустое имя ключа"))

    (let [first-char (first key-text)]

      (if (or (= first-char \")
              (= first-char \'))

        (let [[key end-index]
              (parse-quoted-string
                key-text 1 line first-char)]

          (when-not (= (skip-ws key-text end-index)
                       (.length key-text))

            (parse-error line "Некорректное имя ключа"))

          key)

        (if (re-matches bare-key-pattern key-text)
          key-text
          (parse-error line
            (str "Некорректное имя ключа: " key-text)))))))

;; ============================================================
;; Создание вложенных таблиц
;; ============================================================

(defn ensure-table
  [root path explicit-tables line]

  (loop [current root
         remaining path
         prefix []]

    (let [key (first remaining)
          full-path (conj prefix key)]

      (when-not (.containsKey ^Map current key)
        (.put ^Map current key (LinkedHashMap.)))

      (let [child (.get ^Map current key)]

        (when-not (instance? Map child)
          (parse-error line
            (str "Невозможно создать таблицу: конфликт с ключом " key)))

        (if (= 1 (count remaining))

          (do
            (when (contains? explicit-tables full-path)
              (parse-error line
                "Таблица объявлена повторно"))

            [child (conj explicit-tables full-path)])

          (recur child (rest remaining) full-path))))))

;; ============================================================
;; Разбор TOML
;; ============================================================

(defn parse-assignment [current line-text line-number]

  (let [eq-index (find-equals-index line-text)]

    (when (= eq-index -1)
      (parse-error line-number
        "Отсутствует знак равенства"))

    (let [key
          (parse-key
            (subs line-text 0 eq-index)
            line-number)

          value-text
          (subs line-text (inc eq-index))

          [value end-index]
          (parse-value value-text 0 line-number)

          end-index
          (skip-ws value-text end-index)]

      (when-not (= end-index (.length value-text))
        (parse-error line-number
          "Лишние символы после значения"))

      (when (.containsKey ^Map current key)
        (parse-error line-number
          (str "Повторное объявление ключа: " key)))

      (.put ^Map current key value))))

(defn parse-toml [content]

  (let [root (LinkedHashMap.)]

    (loop [lines (seq (str/split content #"\r?\n" -1))
           line-number 1
           current root
           explicit-tables #{}]

      (if (nil? lines)

        root

        (let [raw-line (first lines)

              line-text
              (str/trim (strip-comment raw-line))]

          (cond

            (empty? line-text)

            (recur (next lines)
                   (inc line-number)
                   current
                   explicit-tables)

            (.startsWith line-text "[")

            (do

              (when-not
                (and (> (count line-text) 2)
                     (= (first line-text) \[)
                     (= (last line-text) \]))

                (parse-error line-number
                  "Некорректное объявление таблицы"))

              (let [section-text
                    (subs line-text 1 (dec (count line-text)))

                    path
                    (mapv str/trim
                      (str/split section-text #"\." -1))]

                (when (some
                        #(not (re-matches bare-key-pattern %))
                        path)

                  (parse-error line-number
                    "Некорректное имя таблицы"))

                (let [[table new-explicit-tables]
                      (ensure-table
                        root path explicit-tables line-number)]

                  (recur (next lines)
                         (inc line-number)
                         table
                         new-explicit-tables))))

            :else

            (do
              (parse-assignment
                current line-text line-number)

              (recur (next lines)
                     (inc line-number)
                     current
                     explicit-tables))))))))

;; ============================================================
;; Экранирование строк JSON
;; ============================================================

(defn escape-json [^String s]

  (let [out (StringBuilder.)]

    (.append out \")

    (doseq [ch s]

      (let [code (int ch)]

        (case code

          34 (.append out "\\\"")
          92 (.append out "\\\\")
          8  (.append out "\\b")
          12 (.append out "\\f")
          10 (.append out "\\n")
          13 (.append out "\\r")
          9  (.append out "\\t")

          (if (< code 32)

            (.append out
              (format "\\u%04x" code))

            (.append out ch)))))

    (.append out \")

    (.toString out)))

;; ============================================================
;; Формирование JSON с отступами
;; ============================================================

(defn indentation [depth]
  (apply str (repeat (* depth 2) " ")))

(declare json-value)

(defn json-object [^Map value depth]

  (let [entries (seq (.entrySet value))]

    (if (empty? entries)

      "{}"

      (str
        "{\n"

        (str/join
          ",\n"

          (map
            (fn [entry]

              (str
                (indentation (inc depth))

                (escape-json (.getKey entry))

                ": "

                (json-value
                  (.getValue entry)
                  (inc depth))))

            entries))

        "\n"
        (indentation depth)
        "}"))))

(defn json-array [values depth]

  (if (empty? values)

    "[]"

    (str
      "[\n"

      (str/join
        ",\n"

        (map
          (fn [value]

            (str
              (indentation (inc depth))

              (json-value value (inc depth))))

          values))

      "\n"
      (indentation depth)
      "]")))

(defn json-value [value depth]

  (cond

    (string? value)
    (escape-json value)

    (true? value)
    "true"

    (false? value)
    "false"

    (instance? BigInteger value)
    (.toString ^BigInteger value)

    (instance? BigDecimal value)
    (.toPlainString ^BigDecimal value)

    (instance? Map value)
    (json-object value depth)

    (sequential? value)
    (json-array value depth)

    :else
    (throw
      (ex-info
        (str "Неподдерживаемый тип JSON: " (type value))
        {}))))

(defn to-json [value]
  (json-value value 0))

;; ============================================================
;; Главная функция
;; ============================================================

(defn -main [& args]

  (if-not (<= 1 (count args) 2)

    (do
      (binding [*out* *err*]
        (println
          "Использование: clojure -M -m main input.toml [output.json]"))

      (System/exit 1))

    (try

      (let [input-file (first args)

            output-file (second args)

            content
            (slurp input-file :encoding "UTF-8")

            parsed
            (parse-toml content)

            result
            (str (to-json parsed) "\n")]

        (if output-file

          (do
            (spit output-file result :encoding "UTF-8")
            (println (str "JSON успешно сохранён: " output-file)))

          (print result)))

      (catch Exception e

        (binding [*out* *err*]
          (println
            (str "Ошибка: " (.getMessage e))))

        (System/exit 1)))))
