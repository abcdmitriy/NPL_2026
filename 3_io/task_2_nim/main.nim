
import os, strutils, tables, sequtils, unicode, algorithm

type
  ParagraphEntry = tuple[idx: int, text: string]
  ReportEntry = tuple[firstIdx: int, line: string]

# Реализация хеша FNV-1a (64 бита)
proc fnv1a64(s: string): uint64 =
  var h: uint64 = 0xcbf29ce484222325'u64
  for c in s:
    h = h xor uint64(ord(c))
    h = h * 0x100000001b3'u64
  return h

# Проверка, состоит ли строка только из пробельных символов
proc isBlankLine(s: string): bool =
  for r in toRunes(s):
    if not isWhiteSpace(r):
      return false
  return true

# Нормализация текста с поддержкой Unicode
proc normalize(s: string): string =
  let lowered = toLower(s)
  var pendingSpace = false

  for r in toRunes(lowered):
    if isWhiteSpace(r):
      if result.len > 0:
        pendingSpace = true
    else:
      if pendingSpace:
        result.add(' ')
        pendingSpace = false
      result.add(r)

# Разделение текста на абзацы (по пустой строке)
proc splitParagraphs(text: string): seq[string] =
  var current = ""

  for line in text.splitLines():
    if isBlankLine(line):
      if current.len > 0:
        result.add(current)
        current = ""
    else:
      if current.len > 0:
        current.add(' ')
      current.add(line)

  if current.len > 0:
    result.add(current)

# Безопасное сокращение текста по символам Unicode
proc makePreview(s: string; maxChars: int = 50): string =
  let runes = toRunes(s)

  if runes.len > maxChars:
    result = $(runes[0 ..< maxChars]) & "..."
  else:
    result = s

when isMainModule:
  # Проверка аргументов и существования файла
  if paramCount() < 1:
    echo "Usage: main <filename>"
    quit(1)

  let filename = paramStr(1)

  if not fileExists(filename):
    echo "Error: file '" & filename & "' not found."
    quit(1)

  let text = readFile(filename)
  let paragraphs = splitParagraphs(text)

  # Группировка по хешу
  var hashGroups = initTable[uint64, seq[ParagraphEntry]]()

  for i, p in paragraphs:
    let norm = normalize(p)
    let h = fnv1a64(norm)

    if not hashGroups.hasKey(h):
      hashGroups[h] = @[]

    hashGroups[h].add((i + 1, norm))

  # Проверка коллизий и формирование отчёта
  var reportEntries: seq[ReportEntry] = @[]

  for h, group in hashGroups:
    var realGroups: seq[seq[ParagraphEntry]] = @[]

    for item in group:
      var found = false

      for rg in realGroups.mitems:
        if rg[0].text == item.text:
          rg.add(item)
          found = true
          break

      if not found:
        realGroups.add(@[item])

    for rg in realGroups:
      if rg.len > 1:
        let indices = rg.mapIt($it.idx).join(", ")
        let preview = makePreview(rg[0].text)

        let line = "Paragraphs [" & indices & "] (" &
                   $rg.len & " times): " & preview

        reportEntries.add((rg[0].idx, line))

  # Сортировка групп по номеру первого абзаца
  reportEntries.sort(proc(a, b: ReportEntry): int =
    cmp(a.firstIdx, b.firstIdx)
  )

  # Вывод результатов
  var reportLines: seq[string] = @[]

  if reportEntries.len == 0:
    let line = "No duplicates found."
    echo line
    reportLines.add(line)
  else:
    for entry in reportEntries:
      echo entry.line
      reportLines.add(entry.line)

  # Запись отчёта в файл
  writeFile("report.txt", reportLines.join("\n") & "\n")

  echo "Report saved to report.txt"
