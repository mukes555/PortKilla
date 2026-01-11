import XCTest
import Foundation
@testable import PortKilla

final class ProcessKillerTests: XCTestCase {

    let killer = ProcessKiller()

    func testKillProcessTerminatesProcess() throws {
        // 1. Spawn a process (sleep)
        let process = Process()
        process.launchPath = "/bin/sleep"
        process.arguments = ["100"]
        try process.run()

        let pid = Int(process.processIdentifier)

        // 2. Ensure it's running
        XCTAssertTrue(killer.isProcessRunning(pid), "Process should be running initially")

        // 3. Kill it
        try killer.killProcess(pid: pid)

        // 4. Wait a moment for OS to clean up
        Thread.sleep(forTimeInterval: 0.1)

        // 5. Verify it's gone
        XCTAssertFalse(killer.isProcessRunning(pid), "Process should be terminated")

        // Cleanup just in case
        process.terminate()
    }

    func testKillTreeTerminatesChild() throws {
        // 1. Spawn a parent process that spawns a child
        // We use a shell script to create a hierarchy: sh -> sleep
        // 'sleep 100 & wait' keeps sh alive waiting for sleep.

        let treeProcess = Process()
        treeProcess.launchPath = "/bin/sh"
        treeProcess.arguments = ["-c", "sleep 100 & wait"]
        try treeProcess.run()

        let treePid = Int(treeProcess.processIdentifier)
        Thread.sleep(forTimeInterval: 0.5)

        let scanner = PortScanner()
        let treeChildren = scanner.getChildProcesses(pid: treePid)
        XCTAssertFalse(treeChildren.isEmpty, "Should have child processes")

        let childPid = treeChildren.first?.pid ?? -1

        // 2. Kill the parent tree
        try killer.killProcess(pid: treePid, killTree: true)

        Thread.sleep(forTimeInterval: 0.5)

        // 3. Verify parent is dead
        XCTAssertFalse(killer.isProcessRunning(treePid), "Parent should be dead")

        // 4. Verify child is dead
        if childPid > 0 {
            XCTAssertFalse(killer.isProcessRunning(childPid), "Child process (PID: \(childPid)) should also be dead")
        }

        // Cleanup
        treeProcess.terminate()
    }
}
