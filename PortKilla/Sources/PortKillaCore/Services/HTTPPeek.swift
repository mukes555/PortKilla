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
        /// Where a redirect pointed; it is reported, never followed.
        public let redirect: String?

        /// "200 · text/html · Vite App", or "302 → https://…"
        public var summary: String {
            if let redirect, (300..<400).contains(status) { return "\(status), redirects to \(redirect)" }
            return [String(status), contentType?.split(separator: ";").first.map(String.init), title].compactMap { $0 }.joined(separator: " · ")
        }
    }

    public enum Failure: Error, Equatable {
        case unreachable(String)
        case notHTTP
    }

    /// The most of a body worth reading for a title.
    public static let byteLimit = 65536

    /// Waits at most 1.5 s and reads at most `byteLimit` bytes; a dev server
    /// that hangs or streams must not hang the inspector. Redirects are
    /// reported, not followed: a local server must not send the app elsewhere.
    public static func probe(port: Int, timeout: TimeInterval = 1.5, configuration: URLSessionConfiguration = .ephemeral,
                             completion: @escaping (Swift.Result<Result, Failure>) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return completion(.failure(.notHTTP)) }
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        var request = URLRequest(url: url)
        request.setValue("PortKilla", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-\(byteLimit - 1)", forHTTPHeaderField: "Range")

        let collector = Collector(completion: completion)
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
        collector.session = session
        session.dataTask(with: request).resume()
    }

    /// Gathers the response, stops at the byte limit, refuses redirects, and
    /// answers exactly once.
    final class Collector: NSObject, URLSessionDataDelegate {
        private let completion: (Swift.Result<Result, Failure>) -> Void
        private var response: HTTPURLResponse?
        private var body = Data()
        private var answered = false
        var session: URLSession?

        init(completion: @escaping (Swift.Result<Result, Failure>) -> Void) {
            self.completion = completion
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            self.response = response
            completionHandler(nil)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            self.response = response as? HTTPURLResponse
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            body.append(data)
            if body.count >= HTTPPeek.byteLimit {
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            defer { session.finishTasksAndInvalidate() }
            guard !answered else { return }
            answered = true
            let cancelled = (error as? URLError)?.code == .cancelled
            if let error, !cancelled {
                return completion(.failure(.unreachable(error.localizedDescription)))
            }
            guard let http = response else { return completion(.failure(.notHTTP)) }
            let text = String(decoding: body.prefix(HTTPPeek.byteLimit), as: UTF8.self)
            completion(.success(Result(
                status: http.statusCode,
                server: http.value(forHTTPHeaderField: "Server"),
                contentType: http.value(forHTTPHeaderField: "Content-Type"),
                title: HTTPPeek.title(in: text),
                redirect: http.value(forHTTPHeaderField: "Location")
            )))
        }
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
