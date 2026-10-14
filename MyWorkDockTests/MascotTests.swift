import XCTest
@testable import MyWorkDock

final class DockTrashTests: XCTestCase {
    func testWindowSitsOnTheTrashWithRoomForTheBubble() {
        // Trash at x 1640…1700, y 1047…1111 in top-left (AX) coordinates on a 1112-pt-tall primary screen.
        let trash = CGRect(x: 1640, y: 1047, width: 60, height: 64)
        let f = MascotGeometry.windowFrame(trashAX: trash, primaryHeight: 1112)
        XCTAssertEqual(f.size, MascotGeometry.window)
        XCTAssertEqual(f.minX + MascotGeometry.characterCenterX, trash.midX, "character centred on the trash")
        // Cocoa y is bottom-up: the window's bottom edge is the seat, a little inside the lid.
        XCTAssertEqual(f.minY, 1112 - (trash.minY + MascotGeometry.seatSink))
    }

    func testFallbackIsBottomRightAboveTheDock() {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let visible = CGRect(x: 0, y: 74, width: 1710, height: 1000)
        let f = MascotGeometry.fallbackFrame(screen: screen, visible: visible)
        XCTAssertEqual(f.minY, 74 - MascotGeometry.seatSink)
        XCTAssertEqual(f.minX + MascotGeometry.characterCenterX, 1710 - 48)
    }
}

final class MascotNoteTests: XCTestCase {
    private func s(_ id: String, _ state: AgentState, project: String = "shop") -> AgentSession {
        AgentSession(id: id, agent: "claude", cwd: "/w/\(project)", project: project, state: state, updatedAt: Date())
    }

    func testFinishingWorkProducesADoneNote() {
        XCTAssertEqual(MascotNotes.done(previous: [s("a", .working)], current: [s("a", .idle)], title: { _ in "Fix checkout" }), "Done: Fix checkout")
        XCTAssertEqual(MascotNotes.done(previous: [s("a", .working)], current: [s("a", .idle)], title: { _ in nil }), "Done: shop")
        XCTAssertNil(MascotNotes.done(previous: [s("a", .idle)], current: [s("a", .idle)], title: { _ in nil }))
        XCTAssertNil(MascotNotes.done(previous: [], current: [s("a", .idle)], title: { _ in nil }))
    }

    func testKindsAreStableAndNamed() {
        XCTAssertEqual(MascotKind.allCases.map(\.rawValue), ["kunoichi", "robot", "cat", "boo"])
        XCTAssertEqual(MascotKind.kunoichi.name, "Kunoichi")
    }
}
