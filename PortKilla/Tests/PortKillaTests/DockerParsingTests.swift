import XCTest
@testable import PortKilla

final class DockerParsingTests: XCTestCase {

    func testParsesSingleMapping() {
        let map = DockerService.parsePortMap("0.0.0.0:5432->5432/tcp::my-postgres")
        XCTAssertEqual(map[5432], "my-postgres")
    }

    func testParsesMultipleMappingsPerContainer() {
        let map = DockerService.parsePortMap("0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp::web")
        XCTAssertEqual(map[80], "web")
        XCTAssertEqual(map[443], "web")
    }

    func testParsesIPv6Mapping() {
        let map = DockerService.parsePortMap(":::8080->8080/tcp::api")
        XCTAssertEqual(map[8080], "api")
    }

    func testIgnoresUnpublishedPortsAndGarbage(){
        let map = DockerService.parsePortMap("""
        6379/tcp::redis-no-publish
        garbage line without separator
        """)
        XCTAssertTrue(map.isEmpty)
    }
}
