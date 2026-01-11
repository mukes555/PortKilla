import XCTest
import Foundation
@testable import PortKilla

final class ProcessTreeTests: XCTestCase {
    
    func testGetChildProcessesFindsChild() throws {
        // 1. Spawn a child process (sleep)
        let process = Process()
        process.launchPath = "/bin/sleep"
        process.arguments = ["10"]
        try process.run()
        
        let childPid = Int(process.processIdentifier)
        
        // Ensure cleanup
        addTeardownBlock {
            process.terminate()
        }
        
        // Allow some time for the process to start and be registered by the OS
        Thread.sleep(forTimeInterval: 0.5)
        
        // 2. Get current process PID (the parent)
        let myPid = Int(ProcessInfo.processInfo.processIdentifier)
        
        // 3. Scan for children
        let scanner = PortScanner()
        let children = scanner.getChildProcesses(pid: myPid)
        
        // 4. Verify the child is found
        // Note: The test runner might have other children, so we just check for existence
        let found = children.contains(where: { $0.pid == childPid })
        
        XCTAssertTrue(found, "PortScanner should find the spawned child process (PID: \(childPid)) for parent (PID: \(myPid))")
        
        if found {
            let childInfo = children.first(where: { $0.pid == childPid })!
            XCTAssertTrue(childInfo.name.contains("sleep"), "Child process name should contain 'sleep', got '\(childInfo.name)'")
        }
    }
}
