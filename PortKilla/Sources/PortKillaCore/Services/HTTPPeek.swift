import Foundation

/// One GET to a local web server, on request or with the opt-in preference:
/// status, server, content type, and the page title, so a port can be told
/// apart from its neighbours without opening a browser. Never automatic
/// without the preference; a request is still a request.
public enum HTTPPeek {
    public struct Result: Equatable {
        public let status: Int
        public let server: String?
        public let contentType: String?
        public let title: String?
        public let finalURL: String?

        /// "200 · text/html · Vite App"
        public var summary: String {
            [String(status), contentType?.split(separator: ";").first.map(String.init), title].compactMap { $0 }.joined(separator: " · ")
        }
    }

    public enum Failure: Error, Equatable {
        case unreachable(String)
        case notHTTP
    }

    /// Reads at most 64 KB and waits at most 1.5 s; a dev server that hangs
    /// must not hang the inspector.
    public static func probe(port: Int, timeout: TimeInterval = 1.5, completion: @escaping (Swift.Result<Result, Failure>) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return completion(.failure(.notHTTP)) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        var request = URLRequest(url: url)
        request.setValue("PortKilla", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")

        let session = URLSession(configuration: configuration)
        let task = session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
            if let error {
                return completion(.failure(.unreachable(error.localizedDescription)))
            }
            guard let http = response as? HTTPURLResponse else { return completion(.failure(.notHTTP)) }
            let body = String(decoding: (data ?? Data()).prefix(65536), as: UTF8.self)
            completion(.success(Result(
                status: http.statusCode,
                server: http.value(forHTTPHeaderField: "Server"),
                contentType: http.value(forHTTPHeaderField: "Content-Type"),
                title: title(in: body),
                finalURL: http.url?.absoluteString
            )))
        }
        task.resume()
    }

    /// The first <title>, whitespace collapsed, capped; nil when there is none.
    public static func title(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let openEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title>", options: .caseInsensitive, range: openEnd.upperBound..<html.endIndex) else { return nil }
        let raw = html[openEnd.upperBound..<close.lowerBound]
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(80))
    }
}
