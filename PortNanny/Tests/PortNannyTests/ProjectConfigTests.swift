import XCTest
@testable import PortNannyCore

/// Phase C2: the port a project's files name, and drift away from it.
final class ProjectConfigTests: XCTestCase {

    func testEnvFilesNamePortsWithPortFirst() {
        let text = """
        # comment
        DB_PORT=5432
        export PORT="3000" # app
        VITE_PORT='5173'
        HOST=localhost
        BADPORT=notanumber
        """
        let ports = ProjectConfig.parseEnv(text, file: ".env")
        XCTAssertEqual(ports.map(\.port), [3000, 5432, 5173], "PORT outranks the *_PORT keys")
        XCTAssertEqual(ports.first?.source, ".env PORT")
        XCTAssertEqual(ports.last?.source, ".env VITE_PORT")
    }

    func testPackageScriptsNamePorts() throws {
        let json = """
        {"scripts": {"dev": "vite --port 5173 --host", "start": "PORT=4000 node server.js", "api": "nodemon -p 3001 api.js", "test": "vitest"}}
        """
        let ports = ProjectConfig.parsePackageScripts(Data(json.utf8))
        XCTAssertEqual(ports.map(\.port), [3001, 5173, 4000], "scripts in name order")
        XCTAssertEqual(ports.map(\.source), ["package.json api", "package.json dev", "package.json start"])
        XCTAssertTrue(ProjectConfig.parsePackageScripts(Data("not json".utf8)).isEmpty)
    }

    func testViteConfigNamesAPort() {
        let text = "export default defineConfig({ server: { port: 5174, strictPort: true } })"
        XCTAssertEqual(ProjectConfig.parseViteConfig(text, file: "vite.config.ts"), [ExpectedPort(port: 5174, source: "vite.config.ts")])
    }

    func testDriftPicksTheNearestExpectedPortOnlyWhenOffAllOfThem() {
        let expected = [ExpectedPort(port: 3000, source: ".env PORT"), ExpectedPort(port: 5173, source: "vite.config.ts")]
        XCTAssertNil(ProjectConfig.drift(from: expected, actual: 3000))
        XCTAssertNil(ProjectConfig.drift(from: [], actual: 3001))
        XCTAssertEqual(ProjectConfig.drift(from: expected, actual: 3001)?.port, 3000)
        XCTAssertEqual(ProjectConfig.drift(from: expected, actual: 5174)?.port, 5173)
    }

    func testProjectFilesAreReadAndReReadWhenTheyChange() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("portnanny-project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        let env = project.appendingPathComponent(".env")
        try "PORT=3000\n".write(to: env, atomically: true, encoding: .utf8)
        try #"{"scripts": {"dev": "next dev -p 3000"}}"#.write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let config = ProjectConfig()
        let now = Date()
        XCTAssertEqual(config.expectedPorts(in: project.path, now: now).map(\.port), [3000], "one port, first mention wins")

        try "PORT=4000\n".write(to: env, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(60)], ofItemAtPath: env.path)
        XCTAssertEqual(config.expectedPorts(in: project.path, now: now.addingTimeInterval(1)).map(\.port), [3000], "trusted for a while")
        XCTAssertEqual(config.expectedPorts(in: project.path, now: now.addingTimeInterval(ProjectConfig.recheckInterval + 1)).map(\.port), [4000, 3000], "re-read once a file changed")
        XCTAssertTrue(config.expectedPorts(in: "/nonexistent/project", now: now).isEmpty)
    }

    func testDriftCommandParsesAndDescribes() {
        XCTAssertEqual(CLIArguments.parse(["drift", "--json"]), .success(.drift(json: true)))
        XCTAssertEqual(CLIArguments.parse(["drift", "--x"]), .failure(.unknownOption("--x", command: "drift")))
        let owner = AgentOwner(name: "Cursor", sessionPid: 7, source: .processTree)
        let item = CLIDrift.Drifted(port: 3001, pid: 812, processName: "node", projectName: "shop", projectPath: "/p/shop",
                                    expected: ExpectedPort(port: 3000, source: ".env PORT"),
                                    heldBy: CLIDrift.Drifted.Holder(pid: 700, processName: "python", agentOwner: owner))
        XCTAssertEqual(CLIDrift.describe(item), "node (PID 812) in shop runs on :3001; .env PORT says :3000, held by python (PID 700, Cursor).")
        XCTAssertTrue(OutputSchemas.render("drift")?.contains("ExpectedPort") == true)
    }
}
