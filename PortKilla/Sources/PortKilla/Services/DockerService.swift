import Foundation

class DockerService {
    static let shared = DockerService()
    
    // Maps a public port to a container name
    // Key: Public Port (Int), Value: Container Name (String)
    private var portContainerMap: [Int: String] = [:]
    
    // Cache control
    private var lastUpdate: Date = Date.distantPast
    private let cacheValidity: TimeInterval = 2.0 // Refresh Docker info every 2 seconds max
    
    // Only attempt to run docker if we think it's installed
    private var isDockerInstalled: Bool = true
    
    func getContainerName(forPort port: Int) -> String? {
        refreshDockerInfoIfNeeded()
        return portContainerMap[port]
    }
    
    private func refreshDockerInfoIfNeeded() {
        if Date().timeIntervalSince(lastUpdate) < cacheValidity {
            return
        }
        
        if !isDockerInstalled {
            return
        }
        
        lastUpdate = Date()
        
        let task = Process()
        task.launchPath = "/usr/local/bin/docker" // Standard path, might need adjustment or searching
        
        // Fallback to /usr/bin/docker or use `which docker` if needed, 
        // but hardcoding common paths is faster for now.
        if !FileManager.default.fileExists(atPath: task.launchPath!) {
            // Try alternative path
            task.launchPath = "/usr/bin/docker"
            if !FileManager.default.fileExists(atPath: task.launchPath!) {
                // Try one more common location for Docker Desktop on Mac
                task.launchPath = "/Applications/Docker.app/Contents/Resources/bin/docker"
                if !FileManager.default.fileExists(atPath: task.launchPath!) {
                     isDockerInstalled = false
                     return
                }
            }
        }
        
        // Command: docker ps --format "{{.Ports}}::{{.Names}}"
        // Output looks like: 0.0.0.0:5432->5432/tcp::my-postgres-db
        task.arguments = ["ps", "--format", "{{.Ports}}::{{.Names}}"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                parseDockerOutput(output)
            }
        } catch {
            print("Failed to run docker command: \(error)")
        }
    }
    
    private func parseDockerOutput(_ output: String) {
        // Clear old map
        var newMap: [Int: String] = [:]
        
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let parts = line.components(separatedBy: "::")
            guard parts.count >= 2 else { continue }
            
            let portsStr = parts[0]
            let containerName = parts[1]
            
            // Ports string examples:
            // "0.0.0.0:5432->5432/tcp"
            // "0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp"
            
            // Split by comma for multiple ports
            let portMappings = portsStr.components(separatedBy: ",")
            
            for mapping in portMappings {
                // Look for pattern "0.0.0.0:PORT->" or ":::PORT->"
                if let rangeArrow = mapping.range(of: "->") {
                    let publicPart = mapping[..<rangeArrow.lowerBound]
                    // publicPart is like "0.0.0.0:5432" or ":::5432"
                    
                    if let lastColon = publicPart.lastIndex(of: ":") {
                        let portStr = publicPart[publicPart.index(after: lastColon)...]
                        if let port = Int(portStr) {
                            newMap[port] = containerName
                        }
                    }
                }
            }
        }
        
        self.portContainerMap = newMap
    }
    
    func stopContainer(name: String) throws {
        let task = Process()
        
        // Reuse path logic (simplified here for brevity, usually should store the valid path)
        var dockerPath = "/usr/local/bin/docker"
        if !FileManager.default.fileExists(atPath: dockerPath) {
             dockerPath = "/usr/bin/docker"
             if !FileManager.default.fileExists(atPath: dockerPath) {
                 dockerPath = "/Applications/Docker.app/Contents/Resources/bin/docker"
             }
        }
        
        task.launchPath = dockerPath
        task.arguments = ["stop", name]
        
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            throw NSError(domain: "DockerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to stop container \(name)"])
        }
        
        // Invalidate cache so UI updates quickly
        lastUpdate = Date.distantPast
    }
}
