"""Run relay-only and disconnected memory captures on a Dirka test device."""

import argparse
import json
from pathlib import Path
import re
import secrets
import subprocess
import time
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
PACKAGE = "com.mgrybyk.dirka"


def node_text(node):
    return node.get("content-desc") or node.get("text") or ""


def named_node(nodes, label):
    return next((node for node in nodes if node_text(node) == label), None)


def bounds(node):
    return tuple(map(int, re.findall(r"[0-9]+", node.get("bounds"))))


def compare(args):
    args.output.mkdir()
    route = "dirka-memory-" + secrets.token_hex(4)
    ui_path = f"/data/local/tmp/{route}.xml"
    adb = ["adb", "-s", args.serial]

    def command(*arguments):
        return subprocess.check_output([*adb, *arguments], text=True, timeout=30).strip()

    def shell(*arguments):
        return command("shell", *arguments)

    def screen():
        shell("uiautomator", "dump", ui_path)
        return list(ET.fromstring(shell("cat", ui_path)).iter("node"))

    def wait_for(find, description):
        for _ in range(8):
            node = find(screen())
            if node is not None:
                return node
            time.sleep(0.4)
        raise RuntimeError(f"Could not locate {description} on the device")

    def button(label):
        return wait_for(lambda nodes: named_node(nodes, label), label)

    def tap(node):
        left, top, right, bottom = bounds(node)
        shell("input", "tap", str((left + right) // 2), str((top + bottom) // 2))

    def client_row(nodes):
        return next((node for node in nodes
                     if node_text(node).partition("\n")[0] == route), None)

    def row_button(nodes, caption):
        row = client_row(nodes)
        if row is None:
            return None
        _, top, _, bottom = bounds(row)
        for node in nodes:
            if node_text(node) == caption:
                _, button_top, _, button_bottom = bounds(node)
                if top <= button_top <= button_bottom <= bottom:
                    return node
        return None

    def launch():
        shell("input", "keyevent", "KEYCODE_WAKEUP")
        shell("wm", "dismiss-keyguard")
        shell("am", "force-stop", PACKAGE)
        shell("am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity")
        button("Add client")

    def add_client(config):
        tap(button("Add client"))
        tap(wait_for(lambda nodes: next((node for node in nodes
                                         if node.get("class") == "android.widget.EditText"), None),
                     "configuration field"))
        settings = [
            "N_T_RELAY_HOST=127.0.0.1",
            f"N_T_RELAY_PORT={config['relayPort']}",
            f"N_T_CRYPT_KEY={config['key']}",
            f"N_T_ROUTE_ID={route}",
            "N_T_CLIENT_BIND_HOST=127.0.0.1",
            f"N_T_CLIENT_PORTS={args.local_port}",
            "N_T_USE_TLS=false",
        ]
        for index, line in enumerate(settings):
            if index:
                shell("input", "keyevent", "KEYCODE_ENTER")
            shell("input", "text", line)
        shell("input", "keyevent", "KEYCODE_BACK")
        tap(button("Save"))
        wait_for(client_row, "temporary client")

    def waiting_for_agent(nodes):
        permission = named_node(nodes, "Allow")
        if permission is not None:
            tap(permission)
            return None
        row = client_row(nodes)
        return row if row is not None and "Waiting for agent" in node_text(row) else None

    def capture(phase):
        print(f"Started {phase}", flush=True)
        with (args.output / f"{phase}.meminfo").open("w") as log:
            subprocess.run(
                ["node", "tool/device-memory.cjs", args.serial,
                 str(args.samples), str(args.interval)],
                cwd=ROOT, stdout=log, check=True,
            )
        print(f"Completed {phase}", flush=True)

    with (args.output / "relay.log").open("w") as relay_log:
        relay = subprocess.Popen(
            ["node", "tool/interop-relay.cjs"], cwd=ROOT, text=True,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=relay_log,
        )
        reverse_port = None
        saved = False
        try:
            config = json.loads(relay.stdout.readline())
            port = f"tcp:{config['relayPort']}"
            command("reverse", "--no-rebind", port, port)
            reverse_port = port
            launch()
            add_client(config)
            saved = True
            launch()
            tap(wait_for(lambda nodes: row_button(nodes, "Connect"), "temporary client Connect button"))
            wait_for(waiting_for_agent, "temporary client Waiting for agent status")
            capture("relay-only")
            launch()
            capture("disconnected-comparison")
        finally:
            relay.stdin.close()
            try:
                relay.wait(timeout=5)
            except subprocess.TimeoutExpired:
                relay.kill()
                relay.wait()
            try:
                if reverse_port is not None:
                    command("reverse", "--remove", reverse_port)
                if saved:
                    launch()
                    tap(wait_for(lambda nodes: row_button(nodes, "Client actions"), "temporary client menu"))
                    tap(button("Delete"))
                    tap(button("Delete"))
            except (RuntimeError, subprocess.SubprocessError) as error:
                print(f"Cleanup incomplete for {route}: {error}", flush=True)
            finally:
                subprocess.run([*adb, "shell", "rm", "-f", ui_path], check=False, timeout=10)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("serial", help="ADB device serial")
    parser.add_argument("output", type=Path, help="New directory for the two captures")
    parser.add_argument("--samples", type=int, default=25)
    parser.add_argument("--interval", type=int, default=300, help="Seconds between samples")
    parser.add_argument("--local-port", type=int, default=38189, help="Unused device port")
    args = parser.parse_args()
    if args.samples < 1 or not 1 <= args.interval <= 2_147_483 or not 1 <= args.local_port <= 65535:
        parser.error("Sample count, interval, or local port is out of range")
    compare(args)


if __name__ == "__main__":
    main()
