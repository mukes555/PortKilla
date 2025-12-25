# PortKilla - macOS Port Manager

![PortKilla - macOS Port Manager](assets/portkilla_banner.png)

**PortKilla** is a lightweight, native macOS menu bar app that helps developers identify and kill processes occupying ports. Instantly fix `EADDRINUSE` errors, terminate stuck Node.js servers, and free up localhost ports without touching the terminal.

## 🚀 Key Features

*   **See What’s Listening**: Lists active listening TCP ports with process name, command, and memory.
*   **Kill by Port**: Kill a single process with confirmation.
*   **Force Kill**: Hold Option while clicking kill to send SIGKILL.
*   **Kill All Dev (Node.js)**: One-click bulk kill for Node.js ports (with a safe list to avoid common IDEs/tools).
*   **Test Radar (Beta)**: Detect common test runners (Jest/Vitest/Mocha/etc) and kill them from a dedicated tab.
*   **History + CSV Export**: View recent kills and export to CSV.

## ⚡ Productivity Shortcuts

*   **Global Access**: Lives in your menu bar for instant availability.
*   **Cmd+R**: Refresh active ports list.
*   **Cmd+K**: Kill all Node.js ports (Ports tab) or all tests (Test Radar tab).
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

This produces `dist/PortKilla-1.0.3.dmg`.

To distribute to other Macs without Gatekeeper prompts, you’ll eventually want Developer ID signing + notarization.

## 🖥 Usage

1.  **Open PortKilla** from your menu bar (Lightning bolt icon).
2.  **View Active Ports**: See a categorized list of Web, Database, and other processes.
3.  **Free a Port**: Hover over any row and click **X** to kill the process.
4.  **Auto-Refresh**: Use the Eye menu to choose Manual/2s/5s/10s/30s.
5.  **History**: Click the Clock icon to view and export history.

## 🤝 Contributing

Contributions are welcome! If you have ideas for new process detection or UI improvements, please open an issue or Pull Request.

## 📄 License

MIT License. Free to use for personal and commercial development.
