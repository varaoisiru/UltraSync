import Foundation

/// RSS 2.0 / RDF / Atom parser producing the same article shape as the
/// Python news.py engine. Uses Foundation's XMLParser; summaries are
/// HTML-stripped the way news.py's _strip_html does.
enum FeedService {

    static func parse(data: Data, source: String) -> [NewsArticle] {
        let parser = XMLParser(data: data)
        let delegate = FeedParserDelegate(source: source)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.articles
    }

    /// Parse a feed publication date (RFC 822 or ISO 8601) for sorting.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let d = rfc.date(from: raw) { return d }
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let d = rfc.date(from: raw) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    static func stripHTML(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "<[^>]+>", with: " ",
                                         options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ",
                                   options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    private let source: String
    private(set) var articles: [NewsArticle] = []

    private var inItem = false
    private var currentElement = ""
    private var text = ""
    private var title = ""
    private var link = ""
    private var summary = ""
    private var published = ""
    private var atomLinkCandidate = ""

    init(source: String) {
        self.source = source
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        if name == "item" || name == "entry" {
            inItem = true
            title = ""; link = ""; summary = ""; published = ""
            atomLinkCandidate = ""
        }
        if inItem {
            currentElement = name
            text = ""
            if name == "link" {
                // Atom: <link rel="alternate" href="..."/>
                if let href = attributeDict["href"] {
                    let rel = attributeDict["rel"] ?? "alternate"
                    if rel == "alternate" { atomLinkCandidate = href }
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inItem, let s = String(data: CDATABlock, encoding: .utf8) { text += s }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if inItem {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "title":
                if title.isEmpty { title = value }
            case "link":
                if !value.isEmpty { link = value }
            case "description", "summary", "content":
                if summary.isEmpty { summary = value }
            case "pubdate", "published", "updated", "date", "dc:date":
                if published.isEmpty { published = value }
            default:
                break
            }
            text = ""
        }
        if name == "item" || name == "entry" {
            let finalLink = link.isEmpty ? atomLinkCandidate : link
            let cleanTitle = FeedService.stripHTML(title)
            if !cleanTitle.isEmpty, !finalLink.isEmpty {
                articles.append(NewsArticle(
                    source: source,
                    title: "[\(source)] \(cleanTitle)",
                    displayTitle: cleanTitle,
                    link: finalLink,
                    summary: FeedService.stripHTML(summary),
                    published: published.isEmpty ? nil : published,
                    fetchedAt: nil,
                    viewed: 0))
            }
            inItem = false
        }
        currentElement = ""
    }
}
