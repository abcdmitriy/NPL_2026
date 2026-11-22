
import Foundation
import FoundationXML

struct RSSItem {
    var title = ""
    var link = ""
    var pubDate = ""
    var description = ""
}

private enum CaptureTarget {
    case feedTitle
    case feedDescription
    case itemTitle
    case itemLink
    case itemPubDate
    case itemDescription
}

private struct TextCapture {
    let target: CaptureTarget
    let depth: Int
    var text = ""
}

final class RSSParserDelegate: NSObject, XMLParserDelegate {
    private(set) var feedTitle = ""
    private(set) var feedDescription = ""
    private(set) var items: [RSSItem] = []
    private(set) var rootElement = ""
    private(set) var hasChannel = false
    private(set) var parseError: String?

    private var elementStack: [String] = []
    private var channelDepth: Int?
    private var itemDepth: Int?
    private var currentItem: RSSItem?
    private var capture: TextCapture?

    private func localName(_ name: String) -> String {
        return name.split(separator: ":")
            .last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        elementStack.append(name)

        if elementStack.count == 1 {
            rootElement = name
        }

        if name == "channel", itemDepth == nil {
            hasChannel = true
            channelDepth = elementStack.count
            return
        }

        if name == "item", channelDepth != nil, itemDepth == nil {
            currentItem = RSSItem()
            itemDepth = elementStack.count
            return
        }

        // Поля непосредственно внутри <item>.
        if let itemDepth, elementStack.count == itemDepth + 1 {
            switch name {
            case "title":
                capture = TextCapture(
                    target: .itemTitle,
                    depth: elementStack.count
                )
            case "link":
                capture = TextCapture(
                    target: .itemLink,
                    depth: elementStack.count
                )
            case "pubdate":
                capture = TextCapture(
                    target: .itemPubDate,
                    depth: elementStack.count
                )
            case "description":
                capture = TextCapture(
                    target: .itemDescription,
                    depth: elementStack.count
                )
            default:
                break
            }
            return
        }

        // Название и описание непосредственно внутри <channel>.
        if let channelDepth,
           itemDepth == nil,
           elementStack.count == channelDepth + 1 {
            switch name {
            case "title":
                capture = TextCapture(
                    target: .feedTitle,
                    depth: elementStack.count
                )
            case "description":
                capture = TextCapture(
                    target: .feedDescription,
                    depth: elementStack.count
                )
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard var activeCapture = capture else { return }
        activeCapture.text += string
        capture = activeCapture
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard var activeCapture = capture,
              let text = String(data: CDATABlock, encoding: .utf8)
        else {
            return
        }

        activeCapture.text += text
        capture = activeCapture
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)

        if let activeCapture = capture,
           activeCapture.depth == elementStack.count {

            let value = activeCapture.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            switch activeCapture.target {
            case .feedTitle:
                feedTitle = value

            case .feedDescription:
                feedDescription = value

            case .itemTitle:
                currentItem?.title = value

            case .itemLink:
                currentItem?.link = value

            case .itemPubDate:
                currentItem?.pubDate = value

            case .itemDescription:
                currentItem?.description = value
            }

            capture = nil
        }

        if name == "item", itemDepth == elementStack.count {
            if let currentItem {
                items.append(currentItem)
            }

            currentItem = nil
            itemDepth = nil
        }

        if name == "channel", channelDepth == elementStack.count {
            channelDepth = nil
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        parseError = error.localizedDescription
    }

    var isValidRSS: Bool {
        return rootElement == "rss" && hasChannel
    }
}

// Декодирование HTML-сущностей.
func decodeHTMLEntities(_ input: String) -> String {
    let namedEntities: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": " ",
        "copy": "©",
        "reg": "®",
        "trade": "™",
        "mdash": "—",
        "ndash": "–",
        "hellip": "…",
        "laquo": "«",
        "raquo": "»",
        "lsquo": "‘",
        "rsquo": "’",
        "ldquo": "“",
        "rdquo": "”",
        "bull": "•",
        "euro": "€",
        "pound": "£",
        "yen": "¥",
        "cent": "¢"
    ]

    let pattern = #"&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z][A-Za-z0-9]+);"#

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return input
    }

    let nsInput = input as NSString
    let matches = regex.matches(
        in: input,
        range: NSRange(location: 0, length: nsInput.length)
    )

    var result = input

    for match in matches.reversed() {
        let entity = nsInput.substring(with: match.range)
        let body = String(entity.dropFirst().dropLast())
        var replacement: String?

        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            if let value = UInt32(body.dropFirst(2), radix: 16),
               let scalar = UnicodeScalar(value) {
                replacement = String(scalar)
            }
        } else if body.hasPrefix("#") {
            if let value = UInt32(body.dropFirst()),
               let scalar = UnicodeScalar(value) {
                replacement = String(scalar)
            }
        } else {
            replacement = namedEntities[body]
        }

        if let replacement,
           let range = Range(match.range, in: result) {
            result.replaceSubrange(range, with: replacement)
        }
    }

    return result
}

// Удаление HTML-тегов и сохранение переносов строк.
func removeHTML(_ html: String) -> String {
    var text = html

    let replacements: [(String, String)] = [
        (#"(?i)<br\s*/?>"#, "\n"),
        (#"(?i)</(p|div|h[1-6]|li|blockquote)\s*>"#, "\n\n"),
        (#"(?i)</(ul|ol)\s*>"#, "\n")
    ]

    for (pattern, replacement) in replacements {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(
                text.startIndex..<text.endIndex,
                in: text
            )

            text = regex.stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: replacement
            )
        }
    }

    let removalPatterns = [
        #"(?is)<!--.*?-->"#,
        #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#,
        #"(?s)<[^>]*>"#
    ]

    for pattern in removalPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(
                text.startIndex..<text.endIndex,
                in: text
            )

            text = regex.stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: ""
            )
        }
    }

    text = decodeHTMLEntities(text)

    text = text.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")

    if let spaces = try? NSRegularExpression(
        pattern: #"[ \t]+\n"#
    ) {
        let range = NSRange(
            text.startIndex..<text.endIndex,
            in: text
        )

        text = spaces.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "\n"
        )
    }

    if let manyNewlines = try? NSRegularExpression(
        pattern: #"\n{3,}"#
    ) {
        let range = NSRange(
            text.startIndex..<text.endIndex,
            in: text
        )

        text = manyNewlines.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "\n\n"
        )
    }

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

// Экранирование специальных символов Markdown.
func escapeMarkdown(_ input: String) -> String {
    let punctuation = CharacterSet(
        charactersIn: "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    )

    var result = ""

    for scalar in input.unicodeScalars {
        if scalar.isASCII && punctuation.contains(scalar) {
            result.append("\\")
        }

        result.unicodeScalars.append(scalar)
    }

    return result
}

func singleLine(_ value: String) -> String {
    return value.split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}

// Подготовка ссылки для Markdown.
func markdownLinkDestination(_ value: String) -> String {
    let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%"
    )

    return value.addingPercentEncoding(
        withAllowedCharacters: allowed
    ) ?? value
}

// Формирование итогового Markdown.
func makeMarkdown(from feed: RSSParserDelegate) -> String {
    let title = singleLine(feed.feedTitle).isEmpty
        ? "RSS-лента"
        : singleLine(feed.feedTitle)

    var output = "# \(escapeMarkdown(title))\n\n"

    let feedDescription = removeHTML(feed.feedDescription)

    if !feedDescription.isEmpty {
        output += "\(escapeMarkdown(feedDescription))\n\n"
    }

    for (index, item) in feed.items.enumerated() {
        let itemTitle = singleLine(item.title).isEmpty
            ? "Запись \(index + 1)"
            : singleLine(item.title)

        let escapedTitle = escapeMarkdown(itemTitle)
        let link = item.link.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if !link.isEmpty {
            output += "## [\(escapedTitle)](<\(markdownLinkDestination(link))>)\n\n"
        } else {
            output += "## \(escapedTitle)\n\n"
        }

        let date = singleLine(item.pubDate)

        output += "**Дата публикации:** \(date.isEmpty ? "не указана" : escapeMarkdown(date))\n\n"

        let description = removeHTML(item.description)

        if !description.isEmpty {
            output += "\(escapeMarkdown(description))\n\n"
        }
    }

    return output.trimmingCharacters(
        in: .whitespacesAndNewlines
    ) + "\n"
}

// Основная функция программы.
func run() throws {
    let arguments = CommandLine.arguments

    guard arguments.count == 3 else {
        throw NSError(
            domain: "RSSMarkdown",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Использование: swift main.swift input.xml output.md"
            ]
        )
    }

    let inputURL = URL(fileURLWithPath: arguments[1])
    let outputURL = URL(fileURLWithPath: arguments[2])

    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        throw NSError(
            domain: "RSSMarkdown",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Входной файл не найден: \(arguments[1])"
            ]
        )
    }

    let data = try Data(contentsOf: inputURL)

    let delegate = RSSParserDelegate()
    let parser = XMLParser(data: data)

    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false

    // Проверка корректности XML.
    guard parser.parse() else {
        let details = delegate.parseError
            ?? parser.parserError?.localizedDescription
            ?? "неизвестная ошибка XML"

        throw NSError(
            domain: "RSSMarkdown",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Некорректный XML: \(details)"
            ]
        )
    }

    // Проверка, что документ является RSS-лентой.
    guard delegate.isValidRSS else {
        throw NSError(
            domain: "RSSMarkdown",
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Файл не является RSS-лентой: ожидаются корневой элемент <rss> и элемент <channel>."
            ]
        )
    }

    guard !delegate.feedTitle.trimmingCharacters(
        in: .whitespacesAndNewlines
    ).isEmpty else {
        throw NSError(
            domain: "RSSMarkdown",
            code: 5,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "В RSS-ленте отсутствует название <channel><title>."
            ]
        )
    }

    let markdown = makeMarkdown(from: delegate)

    try markdown.write(
        to: outputURL,
        atomically: true,
        encoding: .utf8
    )

    print("Готово: \(outputURL.path)")
    print("Записей обработано: \(delegate.items.count)")
}

do {
    try run()
} catch {
    let message = "Ошибка: \(error.localizedDescription)\n"

    FileHandle.standardError.write(
        message.data(using: .utf8) ?? Data()
    )
}
