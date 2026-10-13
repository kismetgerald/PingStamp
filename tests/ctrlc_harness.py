"""Send a real Ctrl+C to a command running in its own console (Windows only).

Ctrl+C handling can't be tested by piping a script's output: a real console
control event has to reach both PowerShell and ping.exe. This helper starts
COMMAND in a new, hidden console, waits DELAY seconds, attaches to that
console, raises CTRL_C_EVENT in it, then prints the exit code and the
console's screen text.

Usage:
    python -I tests/ctrlc_harness.py DELAY COMMAND

Examples (from the repository root):
    python -I tests/ctrlc_harness.py 3.5 "pwsh -NoProfile -File Invoke-PingStamp.ps1 -t 127.0.0.1"
    python -I tests/ctrlc_harness.py 3.5 "powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-PingStamp.ps1 -t 127.0.0.1"

Expected: the reply lines, one blank line, then ping's full statistics
ending with "Control-C".
"""
import ctypes
import subprocess
import sys
import time
from ctypes import wintypes

if sys.platform != "win32":
    sys.exit("ctrlc_harness.py runs on Windows only; on Linux use setsid + kill -INT.")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)


class COORD(ctypes.Structure):
    _fields_ = [("X", ctypes.c_short), ("Y", ctypes.c_short)]


class SMALL_RECT(ctypes.Structure):
    _fields_ = [("Left", ctypes.c_short), ("Top", ctypes.c_short),
                ("Right", ctypes.c_short), ("Bottom", ctypes.c_short)]


class CONSOLE_SCREEN_BUFFER_INFO(ctypes.Structure):
    _fields_ = [("dwSize", COORD), ("dwCursorPosition", COORD),
                ("wAttributes", wintypes.WORD), ("srWindow", SMALL_RECT),
                ("dwMaximumWindowSize", COORD)]


k32.CreateFileW.restype = wintypes.HANDLE
k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                            ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD,
                            wintypes.HANDLE]
k32.GetConsoleScreenBufferInfo.argtypes = [
    wintypes.HANDLE, ctypes.POINTER(CONSOLE_SCREEN_BUFFER_INFO)]
k32.ReadConsoleOutputCharacterW.argtypes = [
    wintypes.HANDLE, wintypes.LPWSTR, wintypes.DWORD, COORD,
    ctypes.POINTER(wintypes.DWORD)]

GENERIC_READ_WRITE = 0xC0000000
FILE_SHARE_READ_WRITE = 3
OPEN_EXISTING = 3
CTRL_C_EVENT = 0


def read_screen():
    """Return the text of the attached console, up to the cursor line."""
    handle = k32.CreateFileW("CONOUT$", GENERIC_READ_WRITE, FILE_SHARE_READ_WRITE,
                             None, OPEN_EXISTING, 0, None)
    info = CONSOLE_SCREEN_BUFFER_INFO()
    k32.GetConsoleScreenBufferInfo(handle, ctypes.byref(info))
    width = info.dwSize.X
    lines = []
    for y in range(info.dwCursorPosition.Y + 1):
        buf = ctypes.create_unicode_buffer(width + 1)
        read = wintypes.DWORD()
        k32.ReadConsoleOutputCharacterW(handle, buf, width, COORD(0, y),
                                        ctypes.byref(read))
        lines.append(buf.value[: read.value].rstrip())
    return lines


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    delay, command = float(sys.argv[1]), sys.argv[2]

    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0  # SW_HIDE
    child = subprocess.Popen(command, creationflags=subprocess.CREATE_NEW_CONSOLE,
                             startupinfo=startup)
    time.sleep(delay)

    # Join the child's console. Ignore Ctrl+C here so only the child reacts;
    # staying attached also keeps the console alive to read afterwards.
    k32.FreeConsole()
    if not k32.AttachConsole(child.pid):
        sys.exit(f"AttachConsole failed (error {ctypes.get_last_error()})")
    k32.SetConsoleCtrlHandler(None, True)
    sent = k32.GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0)

    try:
        exit_code = child.wait(timeout=15)
    except subprocess.TimeoutExpired:
        exit_code = "TIMEOUT (killed)"
        child.kill()

    screen = read_screen()
    k32.FreeConsole()

    print(f"Ctrl+C sent: {bool(sent)}; exit code: {exit_code}")
    print("\n".join(screen))


if __name__ == "__main__":
    main()
