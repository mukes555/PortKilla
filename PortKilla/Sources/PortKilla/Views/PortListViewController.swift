import Cocoa
import Combine

class PortListViewController: NSViewController {

    private let portManager = PortManager()
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var cancellables = Set<AnyCancellable>()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        // Observe port changes
        portManager.$activePorts
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    private func setupUI() {
        // Create table view
        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        
        // Add columns
        let portColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("port"))
        portColumn.title = "Port"
        portColumn.width = 60
        tableView.addTableColumn(portColumn)

        let processColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("process"))
        processColumn.title = "Process"
        processColumn.width = 120
        tableView.addTableColumn(processColumn)

        let memoryColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("memory"))
        memoryColumn.title = "Memory"
        memoryColumn.width = 60
        tableView.addTableColumn(memoryColumn)
        
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "Action"
        actionColumn.width = 50
        tableView.addTableColumn(actionColumn)

        // Wrap in scroll view
        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.frame = NSRect(x: 0, y: 40, width: view.bounds.width, height: view.bounds.height - 40)
        scrollView.autoresizingMask = [.width, .height]

        view.addSubview(scrollView)
        
        // Add "Kill All Node" button at bottom
        let killAllButton = NSButton(title: "Kill All Node.js", target: self, action: #selector(killAllNode))
        killAllButton.frame = NSRect(x: 10, y: 10, width: 120, height: 24)
        view.addSubview(killAllButton)
        
        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        refreshButton.frame = NSRect(x: 140, y: 10, width: 80, height: 24)
        view.addSubview(refreshButton)
        
        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quitButton.frame = NSRect(x: 330, y: 10, width: 60, height: 24)
        view.addSubview(quitButton)
    }
    
    @objc func killAllNode() {
        portManager.killAllPorts(ofType: .nodejs)
    }
    
    @objc func refresh() {
        portManager.refresh()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func killPort(_ sender: NSButton) {
        let row = sender.tag
        if row >= 0 && row < portManager.activePorts.count {
            let portInfo = portManager.activePorts[row]
            portManager.killPort(portInfo)
        }
    }
}

// MARK: - Table View Data Source
extension PortListViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return portManager.activePorts.count
    }
}

// MARK: - Table View Delegate
extension PortListViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let portInfo = portManager.activePorts[row]
        
        if tableColumn?.identifier.rawValue == "action" {
            let button = NSButton(title: "Kill", target: self, action: #selector(killPort(_:)))
            button.tag = row
            button.bezelStyle = .inline
            return button
        }
        
        let cellView = NSTableCellView()
        let textField = NSTextField()
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.isEditable = false
        textField.frame = NSRect(x: 0, y: 0, width: (tableColumn?.width ?? 100), height: 17)

        switch tableColumn?.identifier.rawValue {
        case "port":
            textField.stringValue = ":\(portInfo.port)"
            textField.textColor = portInfo.type.color
        case "process":
            textField.stringValue = portInfo.processName
            if let project = portInfo.projectName {
                textField.stringValue += " (\(project))"
            }
        case "memory":
            textField.stringValue = portInfo.memoryUsage
        default:
            break
        }

        cellView.addSubview(textField)
        return cellView
    }
}
