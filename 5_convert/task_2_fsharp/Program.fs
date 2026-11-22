open System
open System.Collections.Generic
open System.Globalization
open System.IO
open System.Text
open System.Text.Encodings.Web
open System.Text.Json
open System.Text.Json.Nodes
open System.Text.RegularExpressions

exception BibTeXParseException of int * string

type private BibValue =
    | TextValue of string
    | NumberValue of int64

type BibTeXParser(source: string) =
    let mutable position = 0
    let macros = Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)

    do
        macros["jan"] <- "January"
        macros["feb"] <- "February"
        macros["mar"] <- "March"
        macros["apr"] <- "April"
        macros["may"] <- "May"
        macros["jun"] <- "June"
        macros["jul"] <- "July"
        macros["aug"] <- "August"
        macros["sep"] <- "September"
        macros["oct"] <- "October"
        macros["nov"] <- "November"
        macros["dec"] <- "December"

    member private _.IsAtEnd = position >= source.Length

    member private this.Peek() =
        if this.IsAtEnd then '\000' else source[position]

    member private this.Advance() =
        if this.IsAtEnd then
            '\000'
        else
            let current = source[position]
            position <- position + 1
            current

    member private this.CurrentLine =
        let mutable line = 1
        for index = 0 to position - 1 do
            if source[index] = '\n' then
                line <- line + 1
        line

    member private this.Fail(message: string) =
        raise (BibTeXParseException(this.CurrentLine, message))

    member private this.Expect(expected: char) =
        if this.Peek() <> expected then
            this.Fail(sprintf "Ожидался символ '%c'." expected)
        else
            position <- position + 1

    member private this.SkipWhitespaceAndComments() =
        let mutable keepSkipping = true

        while keepSkipping && not this.IsAtEnd do
            let current = this.Peek()

            if Char.IsWhiteSpace(current) || current = '\uFEFF' then
                position <- position + 1
            elif current = '%' then
                while not this.IsAtEnd && this.Peek() <> '\n' do
                    position <- position + 1
            else
                keepSkipping <- false

    member private this.ReadIdentifier() =
        let start = position

        let isIdentifierCharacter (character: char) =
            Char.IsLetterOrDigit(character)
            || character = '_'
            || character = '-'
            || character = ':'
            || character = '.'

        while not this.IsAtEnd && isIdentifierCharacter (this.Peek()) do
            position <- position + 1

        if position = start then
            this.Fail("Ожидалось имя типа записи, поля или макроса.")

        source.Substring(start, position - start)

    member private this.ValueToString(value: BibValue) =
        match value with
        | TextValue text -> text
        | NumberValue number -> number.ToString(CultureInfo.InvariantCulture)

    member private this.ReadBracedValue() =
        this.Expect('{')
        let result = StringBuilder()
        let mutable depth = 1

        while depth > 0 && not this.IsAtEnd do
            let current = this.Advance()

            if current = '{' then
                depth <- depth + 1
                result.Append(current) |> ignore
            elif current = '}' then
                depth <- depth - 1
                if depth > 0 then
                    result.Append(current) |> ignore
            else
                result.Append(current) |> ignore

        if depth <> 0 then
            this.Fail("Не закрыто значение в фигурных скобках.")

        result.ToString()

    member private this.ReadQuotedValue() =
        this.Expect('"')
        let result = StringBuilder()
        let mutable closed = false

        while not closed && not this.IsAtEnd do
            let current = this.Advance()

            if current = '"' then
                closed <- true
            elif current = '\\' && not this.IsAtEnd && this.Peek() = '"' then
                this.Advance() |> ignore
                result.Append('"') |> ignore
            else
                result.Append(current) |> ignore

        if not closed then
            this.Fail("Не закрыто значение в двойных кавычках.")

        result.ToString()

    member private this.ReadBareValue(closing: char) =
        let start = position

        while not this.IsAtEnd
              && not (Char.IsWhiteSpace(this.Peek()))
              && this.Peek() <> '#'
              && this.Peek() <> ','
              && this.Peek() <> closing do
            position <- position + 1

        if position = start then
            this.Fail("Ожидалось значение поля.")

        let token = source.Substring(start, position - start)
        let mutable number = 0L

        if Int64.TryParse(token, NumberStyles.Integer, CultureInfo.InvariantCulture, &number) then
            NumberValue number
        else
            match macros.TryGetValue(token) with
            | true, macroValue ->
                let mutable macroNumber = 0L
                if Int64.TryParse(macroValue, NumberStyles.Integer, CultureInfo.InvariantCulture, &macroNumber) then
                    NumberValue macroNumber
                else
                    TextValue macroValue
            | false, _ -> TextValue token

    member private this.ParseAtom(closing: char) =
        this.SkipWhitespaceAndComments()

        match this.Peek() with
        | '{' -> TextValue(this.ReadBracedValue())
        | '"' -> TextValue(this.ReadQuotedValue())
        | '\000' -> this.Fail("Неожиданный конец файла при чтении значения.")
        | _ -> this.ReadBareValue(closing)

    member private this.ParseValueExpression(closing: char) =
        let firstValue = this.ParseAtom(closing)
        let mutable result = firstValue
        this.SkipWhitespaceAndComments()

        while this.Peek() = '#' do
            this.Advance() |> ignore
            let nextValue = this.ParseAtom(closing)
            result <- TextValue(this.ValueToString(result) + this.ValueToString(nextValue))
            this.SkipWhitespaceAndComments()

        result

    member private this.SkipIgnoredBody(opening: char, closing: char) =
        let mutable depth = 1
        let mutable inQuotes = false
        let mutable escaped = false

        while depth > 0 && not this.IsAtEnd do
            let current = this.Advance()

            if inQuotes then
                if current = '"' && not escaped then
                    inQuotes <- false

                if current = '\\' && not escaped then
                    escaped <- true
                else
                    escaped <- false
            else
                if current = '"' then
                    inQuotes <- true
                elif current = opening then
                    depth <- depth + 1
                elif current = closing then
                    depth <- depth - 1

        if depth > 0 then
            this.Fail("Не закрыта запись-комментарий или преамбула.")

    member private this.ParseStringEntry(closing: char) =
        this.SkipWhitespaceAndComments()
        let macroName = this.ReadIdentifier()
        this.SkipWhitespaceAndComments()
        this.Expect('=')

        let macroValue =
            this.ParseValueExpression(closing)
            |> this.ValueToString

        macros[macroName] <- macroValue

        this.SkipWhitespaceAndComments()
        if this.Peek() = ',' then
            this.Advance() |> ignore
            this.SkipWhitespaceAndComments()

        if this.Peek() <> closing then
            this.Fail("Ожидался конец определения @string.")

        this.Advance() |> ignore

    member private this.AddField(record: JsonObject, fieldName: string, value: BibValue) =
        let normalizedName = fieldName.ToLowerInvariant()

        if record.ContainsKey(normalizedName) then
            this.Fail(sprintf "Поле '%s' указано несколько раз." normalizedName)

        let node: JsonNode =
            if normalizedName = "author" then
                let authors = JsonArray()
                let authorText = this.ValueToString(value)

                Regex.Split(authorText, @"\s+and\s+", RegexOptions.IgnoreCase)
                |> Array.map (fun author -> author.Trim())
                |> Array.filter (fun author -> author.Length > 0)
                |> Array.iter (fun author -> authors.Add(JsonValue.Create(author) :> JsonNode))

                authors :> JsonNode
            else
                match value with
                | NumberValue number -> JsonValue.Create(number) :> JsonNode
                | TextValue text -> JsonValue.Create(text) :> JsonNode

        record[normalizedName] <- node

    member private this.ParseRecord(entryType: string, closing: char) =
        this.SkipWhitespaceAndComments()
        let keyStart = position

        while not this.IsAtEnd && this.Peek() <> ',' && this.Peek() <> closing do
            position <- position + 1

        let citationKey = source.Substring(keyStart, position - keyStart).Trim()

        if String.IsNullOrWhiteSpace(citationKey) then
            this.Fail("У записи отсутствует ключ цитирования.")

        let record = JsonObject()
        record["type"] <- (JsonValue.Create(entryType) :> JsonNode)
        record["key"] <- (JsonValue.Create(citationKey) :> JsonNode)

        if this.Peek() = closing then
            this.Advance() |> ignore
        elif this.Peek() = ',' then
            this.Advance() |> ignore
            let mutable finished = false

            while not finished do
                this.SkipWhitespaceAndComments()

                if this.Peek() = closing then
                    this.Advance() |> ignore
                    finished <- true
                else
                    let fieldName = this.ReadIdentifier()
                    this.SkipWhitespaceAndComments()
                    this.Expect('=')

                    let fieldValue = this.ParseValueExpression(closing)
                    this.AddField(record, fieldName, fieldValue)
                    this.SkipWhitespaceAndComments()

                    if this.Peek() = ',' then
                        this.Advance() |> ignore
                    elif this.Peek() = closing then
                        this.Advance() |> ignore
                        finished <- true
                    else
                        this.Fail("Ожидалась запятая или конец записи после значения поля.")
        else
            this.Fail("После ключа цитирования ожидалась запятая или конец записи.")

        record

    member private this.ParseEntry() =
        this.Expect('@')
        this.SkipWhitespaceAndComments()
        let entryType = this.ReadIdentifier().ToLowerInvariant()
        this.SkipWhitespaceAndComments()

        let opening = this.Peek()
        let closing =
            match opening with
            | '{' -> '}'
            | '(' -> ')'
            | _ -> this.Fail("После типа записи ожидалась '{' или '('.")

        this.Advance() |> ignore

        if entryType = "comment" || entryType = "preamble" then
            this.SkipIgnoredBody(opening, closing)
            None
        elif entryType = "string" then
            this.ParseStringEntry(closing)
            None
        else
            Some(this.ParseRecord(entryType, closing))

    member this.ParseAll() =
        let records = JsonArray()
        this.SkipWhitespaceAndComments()

        while not this.IsAtEnd do
            if this.Peek() <> '@' then
                this.Fail("Ожидалась новая BibTeX-запись, начинающаяся с '@'.")

            match this.ParseEntry() with
            | Some record -> records.Add(record)
            | None -> ()

            this.SkipWhitespaceAndComments()

        records

[<EntryPoint>]
let main arguments =
    if arguments.Length <> 2 then
        eprintfn "Использование: dotnet run -- <input.bib> <output.json>"
        1
    else
        let inputPath = arguments[0]
        let outputPath = arguments[1]

        try
            if not (File.Exists(inputPath)) then
                failwithf "Входной файл не найден: %s" inputPath

            let source = File.ReadAllText(inputPath, Encoding.UTF8)
            let parser = BibTeXParser(source)
            let json = parser.ParseAll()

            let options = JsonSerializerOptions()
            options.WriteIndented <- true
            options.Encoder <- JavaScriptEncoder.UnsafeRelaxedJsonEscaping

            let output = json.ToJsonString(options)
            let fullOutputPath = Path.GetFullPath(outputPath)
            let outputDirectory = Path.GetDirectoryName(fullOutputPath)

            if not (String.IsNullOrEmpty(outputDirectory)) then
                Directory.CreateDirectory(outputDirectory) |> ignore

            File.WriteAllText(fullOutputPath, output, UTF8Encoding(false))
            printfn "Готово: результат записан в %s" outputPath
            0
        with
        | BibTeXParseException(line, message) ->
            eprintfn "Ошибка BibTeX в строке %d: %s" line message
            1
        | error ->
            eprintfn "Ошибка: %s" error.Message
            1