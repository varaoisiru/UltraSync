import Foundation

/// One news article. Field names mirror the Python backend's
/// GET /api/news payload (service.get_news → cache rows); the standalone
/// RSS parser in FeedService produces the same shape locally.
struct NewsArticle: Codable, Identifiable, Equatable {
    var source: String
    var title: String
    var displayTitle: String?
    var link: String
    var summary: String
    var published: String?
    var fetchedAt: String?
    var viewed: Int = 0

    var id: String { link }

    /// Headline without the "[Source] " prefix the Python store embeds.
    var headline: String {
        if let d = displayTitle, !d.isEmpty { return d }
        let prefix = "[\(source)] "
        return title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
    }

    var isUnread: Bool { viewed == 0 }
    var url: URL? { URL(string: link) }

    enum CodingKeys: String, CodingKey {
        case source, title, link, summary, published, viewed
        case displayTitle = "display_title"
        case fetchedAt = "fetched_at"
    }

    init(source: String, title: String, displayTitle: String? = nil,
         link: String, summary: String, published: String? = nil,
         fetchedAt: String? = nil, viewed: Int = 0) {
        self.source = source
        self.title = title
        self.displayTitle = displayTitle
        self.link = link
        self.summary = summary
        self.published = published
        self.fetchedAt = fetchedAt
        self.viewed = viewed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "?"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        published = try c.decodeIfPresent(String.self, forKey: .published)
        fetchedAt = try c.decodeIfPresent(String.self, forKey: .fetchedAt)
        viewed = try c.decodeIfPresent(Int.self, forKey: .viewed) ?? 0
    }
}

/// GET /api/news envelope.
struct NewsResponse: Codable {
    var articles: [NewsArticle]
    var unread: Int
    var totalUnread: Int
    var sources: [String]
    var count: Int

    enum CodingKeys: String, CodingKey {
        case articles, unread, sources, count
        case totalUnread = "total_unread"
    }
}

/// GET /api/news/article envelope (server-cleaned article text).
struct ArticleText: Codable {
    var link: String
    var paragraphs: [String]
}

/// One configured RSS/Atom feed — the same list as the Python app's
/// DEFAULT_FEEDS in ultrasync/config.py.
struct FeedSource: Identifiable, Equatable {
    let name: String
    let urlString: String
    var id: String { name }
    var url: URL? { URL(string: urlString) }

    static let all: [FeedSource] = [
        FeedSource(name: "BBC", urlString: "http://feeds.bbci.co.uk/news/rss.xml"),
        FeedSource(name: "CBS", urlString: "https://www.cbsnews.com/latest/rss/main"),
        FeedSource(name: "FOX", urlString: "https://feeds.foxnews.com/foxnews/latest"),
        FeedSource(name: "Ars", urlString: "https://feeds.arstechnica.com/arstechnica/index"),
        FeedSource(name: "Verge", urlString: "https://www.theverge.com/rss/index.xml"),
        FeedSource(name: "Wired", urlString: "https://www.wired.com/feed/rss"),
        FeedSource(name: "TechCrunch", urlString: "https://techcrunch.com/feed/"),
        FeedSource(name: "ScienceDaily", urlString: "https://www.sciencedaily.com/rss/all.xml"),
        FeedSource(name: "NASA", urlString: "https://www.nasa.gov/rss/dyn/breaking_news.rss"),
        FeedSource(name: "Nature", urlString: "https://www.nature.com/nature.rss"),
    ]

    static var names: [String] { all.map(\.name).sorted() }
}
