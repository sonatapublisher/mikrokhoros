#!/usr/bin/env python3
# Copyright © 2026 MikroKhoros contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Exercise the installed console through a real POSIX pseudoterminal."""

import fcntl
import os
import pathlib
import pty
import re
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time


ANSI_SEQUENCE = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")


def read_until(master: int, output: bytearray, marker: bytes, timeout: float) -> None:
    read_until_after(master, output, marker, 0, timeout)


def read_until_after(
    master: int,
    output: bytearray,
    marker: bytes,
    start: int,
    timeout: float,
) -> None:
    deadline = time.monotonic() + timeout
    while marker not in output[start:]:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError(f"terminal smoke test timed out waiting for {marker!r}")
        readable, _, _ = select.select([master], [], [], min(remaining, 0.1))
        if not readable:
            continue
        chunk = os.read(master, 65536)
        if not chunk:
            raise RuntimeError(f"terminal closed before {marker!r}")
        output.extend(chunk)


def drain(master: int, output: bytearray) -> None:
    """Collect bytes emitted between the last marker and process exit."""
    while True:
        readable, _, _ = select.select([master], [], [], 0)
        if not readable:
            return
        try:
            chunk = os.read(master, 65536)
        except OSError:
            return
        if not chunk:
            return
        output.extend(chunk)


def main() -> int:
    if os.name != "posix":
        print("terminal PTY smoke test is POSIX-only; Windows uses native console tests")
        return 0
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <khoros-binary>", file=sys.stderr)
        return 2

    binary = pathlib.Path(sys.argv[1]).resolve()
    if not binary.is_file():
        print(f"khoros binary does not exist: {binary}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="mikrokhoros-pty-") as product_home:
        master, slave = pty.openpty()
        original = termios.tcgetattr(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        environment = os.environ.copy()
        environment.update(
            {
                "MIKROKHOROS_HOME": product_home,
                "TERM": "xterm-256color",
                "NO_COLOR": "",
            }
        )
        process = subprocess.Popen(
            [str(binary)],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=environment,
            close_fds=True,
        )
        output = bytearray()
        try:
            read_until(master, output, "khoros ›".encode(), 10)
            startup = ANSI_SEQUENCE.sub(b"", bytes(output))
            if b"world      not initialized" not in startup:
                raise RuntimeError(
                    "console did not report the missing world honestly: "
                    + repr(startup[-800:])
                )
            if b"adapters -" in startup or b"agent add -" in startup:
                raise RuntimeError("empty console flooded the terminal with command suggestions")

            history_command_start = len(output)
            os.write(master, b"status\r")
            read_until_after(
                master,
                output,
                b"#1  status  success",
                history_command_start,
                10,
            )
            read_until_after(
                master,
                output,
                "khoros ›".encode(),
                history_command_start,
                5,
            )

            history_up_start = len(output)
            os.write(master, b"\x1b[A")
            read_until_after(master, output, b"status", history_up_start, 5)
            recalled_frame = ANSI_SEQUENCE.sub(b"", bytes(output[history_up_start:]))
            if "khoros › status".encode() not in recalled_frame:
                raise RuntimeError(
                    "Up did not recall the newest command: "
                    + repr(recalled_frame[-800:])
                )

            history_down_start = len(output)
            os.write(master, b"\x1b[B")
            read_until_after(master, output, b"\x1b[?25h", history_down_start, 5)
            restored_frame = ANSI_SEQUENCE.sub(b"", bytes(output[history_down_start:]))
            if "khoros › ".encode() not in restored_frame:
                raise RuntimeError(
                    "Down did not restore the pre-history draft: "
                    + repr(restored_frame[-800:])
                )
            if b"adapters" in restored_frame or b"agent add" in restored_frame:
                raise RuntimeError(
                    "Down restored the draft with an unwanted completion palette: "
                    + repr(restored_frame[-800:])
                )

            typed_output_start = len(output)
            os.write(master, b"sta")
            read_until_after(master, output, b"status", typed_output_start, 5)
            typed_output = bytes(output[typed_output_start:])
            frame_origin = b"\x1b[?25l\r\x1b[2K"
            if frame_origin not in typed_output:
                raise RuntimeError(
                    "typed palette frame did not establish column zero: "
                    + repr(typed_output[-800:])
                )
            first_interrupt = len(output)
            os.write(master, b"\x03")
            read_until_after(master, output, b"^C", first_interrupt, 5)

            os.write(master, b"world create\r")
            read_until_after(
                master,
                output,
                b"1/3 world name [optional]",
                first_interrupt,
                5,
            )
            os.write(master, b"manus\r")
            read_until_after(
                master,
                output,
                b"2/3 world template [optional]",
                first_interrupt,
                5,
            )
            os.write(master, b"default-khoros\r")
            confirmation_start = len(output)
            read_until_after(
                master,
                output,
                b"3/3 confirmation behavior [optional]",
                confirmation_start,
                5,
            )
            read_until_after(master, output, b"ask me first", confirmation_start, 5)
            read_until_after(
                master,
                output,
                b"proceed without asking",
                confirmation_start,
                5,
            )
            confirmation_frame = ANSI_SEQUENCE.sub(
                b"", bytes(output[confirmation_start:])
            )
            if b"false" in confirmation_frame or b"true" in confirmation_frame:
                raise RuntimeError(
                    "guided confirmation exposed canonical boolean values: "
                    + repr(confirmation_frame[-800:])
                )
            tab_completion_start = len(output)
            os.write(master, b"\t")
            read_until_after(
                master,
                output,
                b"3/3 confirmation behavior [optional] \xe2\x80\xba ask me first",
                tab_completion_start,
                5,
            )
            form_interrupt = len(output)
            os.write(master, b"\x03")
            read_until_after(master, output, b"^C", form_interrupt, 5)
            read_until_after(master, output, "khoros ›".encode(), form_interrupt, 5)
            os.write(master, b"\x03")
            read_until_after(master, output, b"console: closed", form_interrupt, 5)
            try:
                return_code = process.wait(timeout=10)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError(
                    "console rendered its close marker but did not exit"
                ) from error
            drain(master, output)
            if return_code != 0:
                raise RuntimeError(f"idle Ctrl-C returned {return_code}")
            if b"\x1b[?2004l" not in output or b"\x1b[?25h" not in output:
                raise RuntimeError("terminal capabilities were not restored on exit")
            restored = termios.tcgetattr(slave)
            if restored != original:
                raise RuntimeError(
                    f"POSIX terminal flags were not restored exactly: "
                    f"original={original!r}, restored={restored!r}"
                )
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            os.close(master)
            os.close(slave)

    print("Terminal PTY smoke test passed (120x30)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # pylint: disable=broad-exception-caught
        print(f"terminal PTY smoke test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
