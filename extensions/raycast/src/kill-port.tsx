import { Action, ActionPanel, Icon, List, showToast, Toast, open } from "@raycast/api";
import { execFile } from "child_process";
import { promisify } from "util";
import { useEffect, useState } from "react";

const run = promisify(execFile);

// The app binary doubles as the CLI. Symlinking it as `portnanny` on PATH
// also works; the bundle path is the zero-setup default.
const CLI = "/Applications/PortNanny.app/Contents/MacOS/PortNanny";

interface Port {
  port: number;
  pid: number;
  processName: string;
  memoryUsage: string;
  proto: string;
  bindAddress?: string;
  projectName?: string;
}

export default function KillPort() {
  const [ports, setPorts] = useState<Port[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  async function refresh() {
    setIsLoading(true);
    try {
      const { stdout } = await run(CLI, ["list", "--json"]);
      setPorts(JSON.parse(stdout));
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "PortNanny CLI not found",
        message: "Install PortNanny.app to /Applications first",
      });
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  async function kill(port: Port, force: boolean) {
    try {
      const args = ["kill", String(port.port)];
      if (force) args.push("--force");
      await run(CLI, args);
      await showToast({ style: Toast.Style.Success, title: `Killed ${port.processName} on :${port.port}` });
      await refresh();
    } catch (error) {
      await showToast({ style: Toast.Style.Failure, title: `Failed to kill :${port.port}` });
    }
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search ports or processes…">
      {ports
        .filter((p) => p.proto === "tcp")
        .map((port) => (
          <List.Item
            key={`${port.port}-${port.pid}`}
            icon={Icon.Bolt}
            title={`:${port.port}`}
            subtitle={port.processName + (port.projectName ? ` · ${port.projectName}` : "")}
            accessories={[{ text: port.memoryUsage }, { text: `PID ${port.pid}` }]}
            actions={
              <ActionPanel>
                <Action title="Kill" icon={Icon.XMarkCircle} onAction={() => kill(port, false)} />
                <Action
                  title="Force Kill (SIGKILL)"
                  icon={Icon.ExclamationMark}
                  style={Action.Style.Destructive}
                  onAction={() => kill(port, true)}
                />
                <Action
                  title="Open in Browser"
                  icon={Icon.Globe}
                  onAction={() => open(`http://localhost:${port.port}`)}
                />
                <Action.CopyToClipboard title="Copy Port" content={String(port.port)} />
              </ActionPanel>
            }
          />
        ))}
    </List>
  );
}
