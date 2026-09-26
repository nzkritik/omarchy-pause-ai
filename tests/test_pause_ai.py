"""End-to-end tests for bin/pause-ai against real processes.

A fake agent (a script named `fakeagent` that starts a child) runs as the
foreground job of an interactive bash in a pseudo-terminal, which is exactly
the case where a naive SIGSTOP breaks the terminal. Run with:

    python3 -m unittest discover -s tests
"""

import json
import os
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "bin", "pause-ai")

AGENT = """#!/usr/bin/python3
import subprocess, time
subprocess.Popen(["sleep", "1000"])
time.sleep(1000)
"""


def state(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().rsplit(")", 1)[1].split()[0]
    except FileNotFoundError:
        return "gone"


def children(pid):
    out = []
    for p in os.listdir("/proc"):
        if p.isdigit():
            try:
                with open(f"/proc/{p}/stat") as f:
                    if int(f.read().rsplit(")", 1)[1].split()[1]) == pid:
                        out.append(int(p))
            except (FileNotFoundError, ProcessLookupError):
                pass
    return out


def drain(fd, seconds=0.4):
    out, end = b"", time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                out += os.read(fd, 65536)
            except OSError:
                break
    return out.decode(errors="replace")


class PauseAITest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.chmod(self.tmp.name, 0o700)
        self.state_dir = os.path.join(self.tmp.name, "state")
        os.mkdir(self.state_dir, 0o700)
        self.agent = os.path.join(self.tmp.name, "fakeagent")
        with open(self.agent, "w") as f:
            f.write(AGENT)
        os.chmod(self.agent, 0o755)
        self.shell, self.fd = pty.fork()
        if self.shell == 0:
            os.execvp("bash", ["bash", "--norc", "--noprofile", "-i"])
        drain(self.fd)
        os.write(self.fd, (self.agent + "\n").encode())
        for _ in range(50):
            kids = children(self.shell)
            if kids and children(kids[0]):
                break
            time.sleep(0.1)
        self.agent_pid = children(self.shell)[0]
        self.child_pid = children(self.agent_pid)[0]
        drain(self.fd)

    def tearDown(self):
        for pid in (self.child_pid, self.agent_pid, self.shell):
            try:
                os.kill(pid, signal.SIGCONT)
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            os.waitpid(self.shell, 0)
        except ChildProcessError:
            pass
        self.tmp.cleanup()

    def run_tool(self, *args, ok=True):
        r = subprocess.run([sys.executable, "-I", TOOL, *args, "--name", "fakeagent",
                            "--state-dir", self.state_dir], capture_output=True, text=True)
        if ok:
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return json.loads(r.stdout)

    def test_pause_and_resume_a_foreground_agent(self):
        scan = self.run_tool("scan")["agents"]
        self.assertEqual([(a["pid"], a["name"]) for a in scan], [(self.agent_pid, "fakeagent")])

        out = self.run_tool("pause")
        self.assertEqual(out["frozen_now"], 3)                 # shell, agent, child
        time.sleep(0.3)
        self.assertEqual([state(p) for p in (self.shell, self.agent_pid, self.child_pid)], ["T"] * 3)

        self.run_tool("resume")
        time.sleep(0.5)
        self.assertEqual([state(p) for p in (self.shell, self.agent_pid, self.child_pid)], ["S"] * 3)
        # bash never noticed: no "Stopped", and the agent kept the terminal
        self.assertNotIn("Stopped", drain(self.fd, 0.6))

    def test_a_process_stopped_by_the_user_stays_stopped(self):
        os.kill(self.child_pid, signal.SIGSTOP)               # like Ctrl-Z on a tool
        time.sleep(0.2)
        self.run_tool("pause")
        self.run_tool("resume")
        time.sleep(0.3)
        self.assertEqual(state(self.child_pid), "T")
        self.assertEqual(state(self.agent_pid), "S")

    def test_a_reused_pid_is_never_woken(self):
        self.run_tool("pause")
        path = os.path.join(self.state_dir, "state.json")
        with open(path) as f:
            data = json.load(f)
        for e in data["frozen"]:
            if e["pid"] == self.child_pid:
                e["start"] += 1                                # as if the pid now names another process
        with open(path, "w") as f:
            json.dump(data, f)
        self.run_tool("resume")
        time.sleep(0.3)
        self.assertEqual(state(self.child_pid), "T")
        self.assertEqual(state(self.agent_pid), "S")

    def test_status_and_timed_pause(self):
        until = time.time() + 300
        self.run_tool("pause", "--until", str(until))
        st = self.run_tool("status")
        self.assertTrue(st["paused"])
        self.assertEqual(st["frozen"], 3)
        self.assertAlmostEqual(st["until"], until, places=0)
        self.run_tool("resume")
        self.assertFalse(self.run_tool("status")["paused"])

    def test_pause_with_nothing_running_is_remembered(self):
        for pid in (self.child_pid, self.agent_pid):
            os.kill(pid, signal.SIGKILL)
        time.sleep(0.3)
        self.run_tool("pause")
        self.assertTrue(self.run_tool("status")["paused"])
        self.run_tool("resume")
        self.assertFalse(self.run_tool("status")["paused"])

    def test_refuses_a_shared_state_dir(self):
        os.chmod(self.state_dir, 0o755)
        out = self.run_tool("status", ok=False)
        self.assertIn("private directory", out["error"])


if __name__ == "__main__":
    unittest.main()
