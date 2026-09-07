import XCTest
import Network
@testable import PortKillaCore

/// HTTPPeek against a real socket: what a local dev server sends must not
/// send the app anywhere, or keep it reading.
final class HTTPPeekTests: XCTestCase {

    /// One-shot HTTP responder on a loopback port the kernel picks.
    private final class TinyServer {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "portkilla.tests.tiny-http")
        private let respond: (String) -> Data
        private(set) var requestLines: [String] = []
        var port: Int { Int(listener.port?.rawValue ?? 0) }

        init(respond: @escaping (String) -> Data) throws {
            self.respond = respond
            listener = try NWListener(using: .tcp, on: .any)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled: ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.start(queue: queue)
            ready.wait()
        }

        private func serve(_ connection: NWConnection) {
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
                guard let self else { return connection.cancel() }
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let line = request.components(separatedBy: "\r\n").first ?? ""
                self.requestLines.append(line)
                connection.send(content: self.respond(line), completion: .contentProcessed { _ in connection.cancel() })
            }
        }

        func stop() {
            listener.cancel()
        }
    }

    private func response(status: String, headers: [String], body: String = "") -> Data {
        let head = (["HTTP/1.1 \(status)"] + headers + ["Content-Length: \(body.utf8.count)", "Connection: close", ""]).joined(separator: "\r\n")
        return Data((head + "\r\n" + body).utf8)
    }

    private func probe(_ port: Int) throws -> HTTPPeek.Result {
        let done = expectation(description: "probe :\(port)")
        var outcome: Swift.Result<HTTPPeek.Result, HTTPPeek.Failure>?
        HTTPPeek.probe(port: port, timeout: 3) {
            outcome = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return try XCTUnwrap(outcome).get()
    }

    func testARedirectIsReportedNeverFollowed() throws {
        var elsewhere = ""
        let server = try TinyServer { line in
            if line.hasPrefix("GET / ") {
                return self.response(status: "302 Found", headers: ["Location: \(elsewhere)"])
            }
            return self.response(status: "200 OK", headers: ["Content-Type: text/html"], body: "<title>followed</title>")
        }
        defer { server.stop() }
        elsewhere = "http://127.0.0.1:\(server.port)/elsewhere"

        let result = try probe(server.port)
        XCTAssertEqual(result.status, 302)
        XCTAssertEqual(result.redirect, elsewhere)
        XCTAssertNil(result.title)
        XCTAssertEqual(result.summary, "302, redirects to \(elsewhere)")
        XCTAssertEqual(server.requestLines.count, 1, "the Location was never requested: \(server.requestLines)")
    }

    func testReadingStopsAtTheByteLimit() throws {
        // The title sits past the limit; a server that streams forever must
        // not keep the inspector reading.
        let filler = String(repeating: "x", count: HTTPPeek.byteLimit + 1024)
        let server = try TinyServer { _ in
            self.response(status: "200 OK", headers: ["Content-Type: text/html"], body: "<html>\(filler)<title>late</title></html>")
        }
        defer { server.stop() }

        let result = try probe(server.port)
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(result.contentType, "text/html")
        XCTAssertNil(result.title, "nothing past the byte limit is read")
    }
}
