# PortKilla - macOS Port Manager

![PortKilla - macOS Port Manager](assets/portkilla_banner.png)

**PortKilla** is a lightweight, native macOS menu bar app that helps developers identify and kill processes occupying ports. Instantly fix `EADDRINUSE` errors, terminate stuck Node.js servers, and free up localhost ports without touching the terminal.

## 🚀 Key Features

*   **Kill Processes by Port**: Instantly find which PID is using a port (e.g., 3000, 8080) and terminate it with one click.
*   **Zombie Process Killer**: Identify and force-kill stuck background processes that refuse to quit.
*   **Test Runner Radar**: Automatically detect and clean up lingering test runners (Jest, Vitest) consuming memory in the background.
*   **Context-Aware Actions**: Dedicated shortcuts to "Kill All Node" or "Kill All Tests" for rapid development resets.
*   **Port Monitoring**: Watch specific ports and get notified when they become active.
*   **Session History**: Log active ports and export activity to CSV for debugging.

## ⚡ Productivity Shortcuts

*   **Global Access**: Lives in your menu bar for instant availability.
*   **Cmd+R**: Refresh active ports list.
*   **Cmd+K**: Kill all development processes (Node.js/Python).
*   **Option+Click**: Force kill (SIGKILL) stubborn processes.

## 📦 Installation

### Build from Source
PortKilla is written in native Swift for maximum performance and minimal battery impact.

```bash
git clone https://github.com/yourusername/portkilla.git
cd portkilla/PortKilla
swift build -c release
open .build/release/PortKilla.app
```

## 🖥 Usage

1.  **Open PortKilla** from your menu bar (Lightning bolt icon).
2.  **View Active Ports**: See a categorized list of Web, Database, and other processes.
3.  **Free a Port**: Hover over any row and click **X** to kill the process.
4.  **Auto-Refresh**: Toggle between Manual, 2s, or 5s refresh intervals via the Eye icon.

## 🤝 Contributing

Contributions are welcome! If you have ideas for new process detection or UI improvements, please open an issue or Pull Request.

## 📄 License

MIT License. Free to use for personal and commercial development.
