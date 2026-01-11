# PortKilla - macOS Port Manager

![PortKilla - macOS Port Manager](assets/portkilla_banner.png)

**PortKilla** is a lightweight, native macOS menu bar app that helps developers identify and kill processes occupying ports. Instantly fix `EADDRINUSE` errors, terminate stuck Node.js servers, and free up localhost ports without touching the terminal.

## 🚀 Key Features

*   **See What’s Listening**: Lists active listening TCP ports with process name, command, and memory.
*   **Process Tree View**: Expand any process to see its child processes (e.g., Python spawning worker threads).
*   **Smart Kill**:
    *   **Kill Port**: Terminates the main process.
    *   **Kill Tree**: Automatically terminates child processes (like `sleep` or worker threads) when killing the parent.
    *   **Force Kill**: Hold Option while clicking kill to send SIGKILL.
*   **Docker Integration**: Automatically detects and displays Docker container names next to mapped ports.
*   **Kill All Dev (Node.js)**: One-click bulk kill for Node.js ports (with a safe list to avoid common IDEs/tools).
*   **Test Radar (Beta)**: Detect common test runners (Jest/Vitest/Mocha/etc) and kill them from a dedicated tab.
*   **History + CSV Export**: View recent kills and export to CSV.

## ⚡ Productivity Shortcuts

*   **Global Access**: Lives in your menu bar for instant availability.
*   **Cmd+R**: Refresh active ports list.
*   **Cmd+K**: Kill all Node.js ports (Ports tab) or all tests (Test Radar tab).
*   **Click Row**: Expand/collapse process tree.
*   **Option+Click**: Force kill (SIGKILL) stubborn processes.

## 📦 Installation

### Build from Source
PortKilla is written in native Swift for maximum performance and minimal battery impact.

```bash
git clone https://github.com/mukes555/PortKilla.git
cd PortKilla
./scripts/build.sh
```

Build output lands in `dist/`:

- `dist/PortKilla.app`

Drag `PortKilla.app` to `/Applications`.

### Build a DMG (optional)

```bash
./scripts/build.sh --dmg
```

This produces `dist/PortKilla-1.1.0.dmg`.

To distribute to other Macs without Gatekeeper prompts, you’ll eventually want Developer ID signing + notarization.

## 🖥 Usage

1.  **Open PortKilla** from your menu bar (Lightning bolt icon).
2.  **View Active Ports**: See a categorized list of Web, Database, and other processes.
3.  **Process Tree**: Click on any row to expand and view child processes.
4.  **Free a Port**:
    *   Click **X** to kill.
    *   **Shift+Click X** to kill the entire process tree.
    *   **Option+Click X** to force kill.
5.  **Auto-Refresh**: Use the Eye menu to choose Manual/2s/5s/10s/30s.
6.  **History**: Click the Clock icon to view and export history.

## 🤝 Contributing

Contributions are welcome! If you have ideas for new process detection or UI improvements, please open an issue or Pull Request.

## 📄 License

MIT License. Free to use for personal and commercial development.
