import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class BlogVoiceLibrary {
    static let shared = BlogVoiceLibrary()

    private static let blogBaseURL = URL(string: "https://davidoks.blog")!
    private static let refreshInterval: TimeInterval = 12 * 60 * 60
    private static let maxPromptContextCharacters = 14_000
    private static let sampleCharactersPerPost = 1_250

    var isSyncing = false
    var lastSyncAt: Date?
    var lastErrorMessage: String?
    var syncedPostCount = 0
    var sitePostCount = 0
    var fallbackPostCount = 0
    var totalWordCount = 0
    var recentPostTitles: [String] = []

    @ObservationIgnored private var cachedCorpus: BlogVoiceCorpus?
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    private init() {
        loadCachedCorpus()
    }

    var sourceURLString: String {
        Self.blogBaseURL.absoluteString
    }

    var contextFilePath: String {
        Self.contextFileURL.path
    }

    var statusSummary: String {
        guard let lastSyncAt else {
            return "No synced blog corpus yet."
        }

        var components = [
            "Synced \(syncedPostCount) post\(syncedPostCount == 1 ? "" : "s")",
            "\(totalWordCount) words",
            Self.displayDate(lastSyncAt)
        ]

        if sitePostCount > 0 {
            components.insert("coverage \(syncedPostCount)/\(sitePostCount)", at: 1)
        }

        if fallbackPostCount > 0 {
            components.append("\(fallbackPostCount) fetched from post pages")
        }

        return components.joined(separator: " - ")
    }

    func promptContextIfAvailable() -> String? {
        cachedCorpus?.promptContext(maxCharacters: Self.maxPromptContextCharacters)
    }

    func ensureCorpusAvailable() async -> String? {
        if needsRefresh {
            await syncNow()
        }

        return cachedCorpus?.promptContext(maxCharacters: Self.maxPromptContextCharacters)
    }

    func refreshInBackgroundIfNeeded() {
        guard needsRefresh, syncTask == nil else { return }

        Task { [weak self] in
            await self?.syncNow()
        }
    }

    func syncNow() async {
        if let syncTask {
            await syncTask.value
            return
        }

        isSyncing = true
        lastErrorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let corpus = try await Self.buildCorpus()
                try Self.persist(corpus: corpus)

                await MainActor.run {
                    self.apply(corpus: corpus)
                    self.lastErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                self.isSyncing = false
                self.syncTask = nil
            }
        }

        syncTask = task
        await task.value
    }

    private var needsRefresh: Bool {
        guard let lastSyncAt else { return true }
        return Date().timeIntervalSince(lastSyncAt) >= Self.refreshInterval || cachedCorpus == nil
    }

    private func apply(corpus: BlogVoiceCorpus) {
        cachedCorpus = corpus
        lastSyncAt = corpus.syncedAt
        syncedPostCount = corpus.posts.count
        sitePostCount = corpus.sitePostCount
        fallbackPostCount = corpus.fallbackPagePostCount
        totalWordCount = corpus.totalWordCount
        recentPostTitles = Array(corpus.posts.sorted(by: Self.sortPostsNewestFirst).prefix(5).map(\.title))
    }

    private func loadCachedCorpus() {
        guard let data = try? Data(contentsOf: Self.corpusFileURL),
              let corpus = try? JSONDecoder.blogVoice.decode(BlogVoiceCorpus.self, from: data)
        else {
            return
        }

        apply(corpus: corpus)
    }

    private static func persist(corpus: BlogVoiceCorpus) throws {
        let directory = storageDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder.blogVoice.encode(corpus)
        try data.write(to: corpusFileURL, options: .atomic)
        try corpus.promptReferenceDocument(maxCharacters: maxPromptContextCharacters).write(
            to: contextFileURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func buildCorpus() async throws -> BlogVoiceCorpus {
        let session = makeSession()
        let feedPosts = try await fetchFeedPosts(session: session)
        let sitemapLinks = try await fetchSitemapLinks(session: session)

        var postsByURL = Dictionary(uniqueKeysWithValues: feedPosts.map { ($0.url, $0) })
        var fallbackPagePostCount = 0

        if !sitemapLinks.isEmpty {
            for link in sitemapLinks where postsByURL[link.url] == nil {
                guard let post = try await fetchPostPage(url: link.url, titleHint: link.title, session: session) else {
                    continue
                }
                postsByURL[post.url] = post
                fallbackPagePostCount += 1
            }
        }

        let posts = postsByURL.values.sorted(by: sortPostsNewestFirst)

        guard !posts.isEmpty else {
            throw BlogVoiceError.emptyCorpus
        }

        return BlogVoiceCorpus(
            syncedAt: Date(),
            baseURL: blogBaseURL.absoluteString,
            sitePostCount: sitemapLinks.count,
            fallbackPagePostCount: fallbackPagePostCount,
            posts: posts
        )
    }

    private static func fetchFeedPosts(session: URLSession) async throws -> [BlogVoiceCorpus.Post] {
        let feedURL = blogBaseURL.appendingPathComponent("feed")
        let (data, response) = try await session.data(from: feedURL)
        try validate(response: response, url: feedURL)

        let parser = BlogVoiceFeedParser()
        return try parser.parse(data: data)
            .compactMap { item in
                guard let url = normalizeURL(item.link) else { return nil }
                let bodyText = plainText(fromHTML: item.bodyHTML)
                guard !bodyText.isEmpty else { return nil }

                return BlogVoiceCorpus.Post(
                    title: item.title.isEmpty ? url.lastPathComponent : item.title,
                    subtitle: item.subtitle?.nilIfEmpty,
                    url: url.absoluteString,
                    publishedAt: item.publishedAt,
                    bodyText: bodyText,
                    source: .feed
                )
            }
    }

    private static func fetchSitemapLinks(session: URLSession) async throws -> [SitemapLink] {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: Date())
        var linksByURL: [String: SitemapLink] = [:]
        var consecutiveMisses = 0

        for year in stride(from: currentYear, through: currentYear - 8, by: -1) {
            let sitemapURL = blogBaseURL
                .appendingPathComponent("sitemap")
                .appendingPathComponent(String(year))

            do {
                let html = try await fetchText(url: sitemapURL, session: session)
                let links = parseSitemapLinks(html)

                if links.isEmpty {
                    consecutiveMisses += 1
                } else {
                    consecutiveMisses = 0
                    for link in links {
                        linksByURL[link.url] = link
                    }
                }
            } catch {
                consecutiveMisses += 1
            }

            if consecutiveMisses >= 2 && !linksByURL.isEmpty {
                break
            }
        }

        return linksByURL.values.sorted { $0.url < $1.url }
    }

    private static func fetchPostPage(
        url: String,
        titleHint: String?,
        session: URLSession
    ) async throws -> BlogVoiceCorpus.Post? {
        guard let normalizedURL = normalizeURL(url) else { return nil }
        let html = try await fetchText(url: normalizedURL, session: session)

        guard let encodedBodyHTML = firstCapture(
            in: html,
            pattern: #""body_html":"(.*?)","truncated_body_text":"#,
            options: [.dotMatchesLineSeparators]
        ),
        let bodyHTML = decodeJSONStringFragment(encodedBodyHTML)
        else {
            return nil
        }

        let title = titleHint?.nilIfEmpty ??
            decodeHTMLFragment(firstCapture(in: html, pattern: #"<h1[^>]*>(.*?)</h1>"#, options: [.dotMatchesLineSeparators]) ?? "")
        let subtitle = decodeHTMLFragment(firstCapture(
            in: html,
            pattern: #"<h3[^>]*class="subtitle[^"]*"[^>]*>(.*?)</h3>"#,
            options: [.dotMatchesLineSeparators]
        ) ?? "")

        let publishedAt = firstCapture(in: html, pattern: #""datePublished":"([^"]+)""#)
            .flatMap(parseISO8601Date)
        let bodyText = plainText(fromHTML: bodyHTML)

        guard !bodyText.isEmpty else { return nil }

        return BlogVoiceCorpus.Post(
            title: title.nilIfEmpty ?? normalizedURL.lastPathComponent,
            subtitle: subtitle.nilIfEmpty,
            url: normalizedURL.absoluteString,
            publishedAt: publishedAt,
            bodyText: bodyText,
            source: .page
        )
    }

    private static func fetchText(url: URL, session: URLSession) async throws -> String {
        let (data, response) = try await session.data(from: url)
        try validate(response: response, url: url)

        guard let text = String(data: data, encoding: .utf8) else {
            throw BlogVoiceError.unreadableResponse(url.absoluteString)
        }

        return text
    }

    private static func validate(response: URLResponse, url: URL) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlogVoiceError.invalidResponse(url.absoluteString)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw BlogVoiceError.httpError(url.absoluteString, httpResponse.statusCode)
        }
    }

    private static func parseSitemapLinks(_ html: String) -> [SitemapLink] {
        allCaptures(
            in: html,
            pattern: #"<a href="(https://[^"]+/p/[^"]+)"[^>]*class="sitemap-link"[^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators]
        )
            .compactMap { captures in
                guard captures.count == 2,
                      let url = normalizeURL(captures[0])?.absoluteString
                else {
                    return nil
                }

                return SitemapLink(
                    title: decodeHTMLFragment(captures[1]).nilIfEmpty,
                    url: url
                )
            }
    }

    private static func plainText(fromHTML html: String) -> String {
        let cleanedHTML = html
            .replacingOccurrences(
                of: #"(?s)<div class=\"subscription-widget-wrap-editor\".*?</div></div>"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?s)<p class=\"button-wrapper\".*?</p>"#,
                with: "",
                options: .regularExpression
            )

        guard let data = cleanedHTML.data(using: String.Encoding.utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              )
        else {
            return normalizeText(cleanedHTML.strippingHTML())
        }

        return normalizeText(attributed.string)
    }

    private static func normalizeText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }

        let unwantedLines: Set<String> = [
            "Subscribe",
            "Subscribe now",
            "This Substack is supported by readers like you.",
            "Type your email…"
        ]

        let filteredLines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !unwantedLines.contains($0) }

        return filteredLines
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https")
        else {
            return nil
        }

        return url
    }

    private static func decodeJSONStringFragment(_ fragment: String) -> String? {
        let wrapped = "\"\(fragment)\""
        guard let data = wrapped.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private static func decodeHTMLFragment(_ fragment: String) -> String {
        guard !fragment.isEmpty else { return "" }
        let html = "<span>\(fragment)</span>"

        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              )
        else {
            return fragment
        }

        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        allCaptures(in: text, pattern: pattern, options: options).first?.first
    }

    private static func allCaptures(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let fullRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: fullRange).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private static func parseISO8601Date(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    nonisolated fileprivate static func sortPostsNewestFirst(
        lhs: BlogVoiceCorpus.Post,
        rhs: BlogVoiceCorpus.Post
    ) -> Bool {
        switch (lhs.publishedAt, rhs.publishedAt) {
        case let (left?, right?):
            return left > right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.title < rhs.title
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Shakespeare").appendingPathComponent("BlogVoice")
    }

    private static var corpusFileURL: URL {
        storageDirectory.appendingPathComponent("blog-voice-corpus.json")
    }

    private static var contextFileURL: URL {
        storageDirectory.appendingPathComponent("blog-voice-context.md")
    }
}

private struct BlogVoiceCorpus: Codable {
    struct Post: Codable, Hashable {
        enum Source: String, Codable {
            case feed
            case page
        }

        let title: String
        let subtitle: String?
        let url: String
        let publishedAt: Date?
        let bodyText: String
        let source: Source

        var wordCount: Int {
            bodyText.split(whereSeparator: \.isWhitespace).count
        }

        func voiceSample(maxCharacters: Int) -> String {
            let paragraphs = bodyText
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !paragraphs.isEmpty else {
                return String(bodyText.prefix(maxCharacters))
            }

            let opening = Array(paragraphs.prefix(3))
            let closing = paragraphs.count > 5 ? Array(paragraphs.suffix(2)) : []
            var parts: [String] = []

            if !opening.isEmpty {
                parts.append("[Opening]\n" + opening.joined(separator: "\n\n"))
            }

            if !closing.isEmpty {
                parts.append("[Closing]\n" + closing.joined(separator: "\n\n"))
            }

            if parts.isEmpty {
                parts.append(paragraphs.prefix(4).joined(separator: "\n\n"))
            }

            let combined = parts.joined(separator: "\n\n")
            guard combined.count > maxCharacters else { return combined }

            return String(combined.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    let syncedAt: Date
    let baseURL: String
    let sitePostCount: Int
    let fallbackPagePostCount: Int
    let posts: [Post]

    var totalWordCount: Int {
        posts.reduce(0) { $0 + $1.wordCount }
    }

    func promptContext(maxCharacters: Int) -> String {
        var context = """
        Source: \(baseURL)
        Synced: \(BlogVoiceCorpus.displayDate(syncedAt))
        Coverage: \(posts.count)\(sitePostCount > 0 ? "/\(sitePostCount)" : "") public posts
        Instruction: infer the user's voice, pacing, sentence rhythm, argument structure, and level of specificity from these published samples. Match style without copying distinctive phrasing, examples, or structure too closely.
        """

        for post in posts.sorted(by: BlogVoiceLibrary.sortPostsNewestFirst) {
            let dateLabel = post.publishedAt.map(BlogVoiceCorpus.displayDateOnly) ?? "Unknown date"
            let subtitleLine = post.subtitle.flatMap { $0.nilIfEmpty }.map { "Subtitle: \($0)\n" } ?? ""
            let block = """

            ### \(post.title) - \(dateLabel)
            \(subtitleLine)URL: \(post.url)
            \(post.voiceSample(maxCharacters: 1_250))
            """

            if context.count + block.count > maxCharacters {
                break
            }

            context += block
        }

        return context
    }

    func promptReferenceDocument(maxCharacters: Int) -> String {
        """
        # David Oks Blog Voice Reference

        \(promptContext(maxCharacters: maxCharacters))
        """
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func displayDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct SitemapLink: Hashable {
    let title: String?
    let url: String
}

private struct BlogVoiceFeedItem {
    let title: String
    let subtitle: String?
    let link: String
    let publishedAt: Date?
    let bodyHTML: String
}

private final class BlogVoiceFeedParser: NSObject, XMLParserDelegate {
    private var items: [BlogVoiceFeedItem] = []
    private var currentElement = ""
    private var isInsideItem = false

    private var currentTitle = ""
    private var currentDescription = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var currentContent = ""

    func parse(data: Data) throws -> [BlogVoiceFeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? BlogVoiceError.feedParsingFailed
        }

        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "item" {
            isInsideItem = true
            currentTitle = ""
            currentDescription = ""
            currentLink = ""
            currentPubDate = ""
            currentContent = ""
        }

        currentElement = elementName
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "description":
            currentDescription += string
        case "link":
            currentLink += string
        case "pubDate":
            currentPubDate += string
        case "content:encoded":
            currentContent += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            currentElement = ""
        }

        guard elementName == "item" else { return }
        isInsideItem = false

        items.append(
            BlogVoiceFeedItem(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                publishedAt: DateFormatter.rssPubDate.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)),
                bodyHTML: currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }
}

private enum BlogVoiceError: LocalizedError {
    case feedParsingFailed
    case emptyCorpus
    case invalidResponse(String)
    case unreadableResponse(String)
    case httpError(String, Int)

    var errorDescription: String? {
        switch self {
        case .feedParsingFailed:
            return "Could not parse the blog feed."
        case .emptyCorpus:
            return "The blog sync completed but produced no usable posts."
        case .invalidResponse(let url):
            return "Invalid response while syncing \(url)."
        case .unreadableResponse(let url):
            return "Could not read response body from \(url)."
        case .httpError(let url, let statusCode):
            return "HTTP \(statusCode) while syncing \(url)."
        }
    }
}

private extension JSONDecoder {
    static let blogVoice: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let blogVoice: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension DateFormatter {
    static let rssPubDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func strippingHTML() -> String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
