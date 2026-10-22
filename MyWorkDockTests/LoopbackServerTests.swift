import XCTest
@testable import MyWorkDock

final class LoopbackServerTests: XCTestCase {
    private func get(_ path: String, port: UInt16, host: String = "127.0.0.1") async throws -> (status: Int, body: String) {
        var request = URLRequest(url: URL(string: "http://\(host):\(port)\(path)")!)
        request.timeoutInterval = 3
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
    }

    func testRightStateReturnsTheCodeAndAnswersThePage() async throws {
        let server = LoopbackServer(state: "s1")
        defer { server.stop() }
        let port = try await server.start()
        async let code = server.callback(timeout: 5)
        let page = try await get("/?code=4%2F0Abc&state=s1", port: port)
        XCTAssertEqual(page.status, 200)
        XCTAssertTrue(page.body.contains("signed in"))
        let received = try await code
        XCTAssertEqual(received, "4/0Abc")
    }

    func testAnswerArrivingBeforeTheWaitStartsIsKept() async throws {
        let server = LoopbackServer(state: "s1")
        defer { server.stop() }
        let port = try await server.start()
        _ = try await get("/?code=early&state=s1", port: port)
        let received = try await server.callback(timeout: 5)
        XCTAssertEqual(received, "early")
    }

    func testLoopbackWrongStateAndFavicon() async throws {
        let server = LoopbackServer(state: "s1")
        defer { server.stop() }
        let port = try await server.start()
        async let code = server.callback(timeout: 5)
        let favicon = try await get("/favicon.ico", port: port)
        XCTAssertEqual(favicon.status, 404)
        let forged = try await get("/?code=evil&state=other", port: port)
        XCTAssertEqual(forged.status, 404)
        let noState = try await get("/?code=evil", port: port)
        XCTAssertEqual(noState.status, 404)
        _ = try await get("/?code=good&state=s1", port: port) // none of the above ended the wait
        let received = try await code
        XCTAssertEqual(received, "good")
    }

    func testCancelInTheBrowserThrowsDenied() async throws {
        let server = LoopbackServer(state: "s1")
        defer { server.stop() }
        let port = try await server.start()
        async let code = server.callback(timeout: 5)
        _ = try await get("/?error=access_denied&state=s1", port: port)
        do { _ = try await code; XCTFail("expected denied") } catch { XCTAssertEqual(error as? LoopbackServer.Failure, .denied("access_denied")) }
    }

    func testFlowTimesOut() async throws {
        let server = LoopbackServer(state: "s1")
        defer { server.stop() }
        _ = try await server.start()
        do { _ = try await server.callback(timeout: 0.2); XCTFail("expected a timeout") } catch { XCTAssertEqual(error as? LoopbackServer.Failure, .timeout) }
    }

    func testCancellingTheTaskEndsTheWait() async throws {
        let server = LoopbackServer(state: "s1")
        defer { server.stop() }
        _ = try await server.start()
        let waiting = Task { try await server.callback(timeout: 30) }
        try await Task.sleep(for: .milliseconds(100))
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testStopEndsTheWait() async throws {
        let server = LoopbackServer(state: "s1")
        _ = try await server.start()
        let waiting = Task { try await server.callback(timeout: 30) }
        try await Task.sleep(for: .milliseconds(100))
        server.stop()
        do { _ = try await waiting.value; XCTFail("expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testLoopbackNotReachableOnLAN() async throws {
        let lan = try XCTUnwrap(LocalIP.current(), "needs a network address to prove the listener is loopback-only")
        let server = LoopbackServer(state: "s1")
        defer { server.stop() }
        let port = try await server.start()
        _ = try await get("/favicon.ico", port: port) // reachable through 127.0.0.1 …
        do {
            _ = try await get("/favicon.ico", port: port, host: lan)
            XCTFail("the listener answered on \(lan): it is not bound to 127.0.0.1 only")
        } catch {} // … and refused on the LAN address
    }

    func testInterpretOnlyAcceptsAGetOnTheRootWithTheRightState() {
        func reply(_ line: String) -> LoopbackServer.Reply { LoopbackServer.interpret(line, state: "s") }
        XCTAssertEqual(reply("GET /?code=a&state=s HTTP/1.1"), .code("a"))
        XCTAssertEqual(reply("GET /?error=access_denied&state=s HTTP/1.1"), .denied("access_denied"))
        XCTAssertEqual(reply("POST /?code=a&state=s HTTP/1.1"), .ignore)
        XCTAssertEqual(reply("GET /other?code=a&state=s HTTP/1.1"), .ignore)
        XCTAssertEqual(reply("GET /?code=a&state=x HTTP/1.1"), .ignore)
        XCTAssertEqual(reply("GET /?state=s HTTP/1.1"), .ignore)
        XCTAssertEqual(reply("GET /?code=&state=s HTTP/1.1"), .ignore)
        XCTAssertEqual(reply(""), .ignore)
    }
}
