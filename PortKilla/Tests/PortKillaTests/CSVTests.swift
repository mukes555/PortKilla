import XCTest
@testable import PortKillaCore
@testable import PortKilla

final class CSVTests: XCTestCase {

    func testPlainValuePassesThrough() {
        XCTAssertEqual(CSV.field("node"), "node")
    }

    func testCommasAndQuotesAreQuoted() {
        XCTAssertEqual(CSV.field("a,b"), "\"a,b\"")
        XCTAssertEqual(CSV.field("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testFormulaPrefixesAreDefused() {
        XCTAssertEqual(CSV.field("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(CSV.field("+1234"), "'+1234")
        XCTAssertEqual(CSV.field("@cmd"), "'@cmd")
    }
}
