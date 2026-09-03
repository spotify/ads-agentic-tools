#!/usr/bin/env python3
"""Cross-platform credential storage for the Spotify Ads API plugin.

Usage:
    credential-helper.py get
    credential-helper.py set --secret SECRET
    credential-helper.py delete

macOS: delegates to the security command (Keychain).
Windows: uses Win32 Credential Manager via ctypes.
Linux: delegates to secret-tool (libsecret).

Exit codes: 0 success, 1 not found, 2 error, 3 missing tool.
"""
import argparse
import subprocess
import sys

SERVICE = "spotify-ads-api-client-secret"
ACCOUNT = "spotify-ads-api"


# -- macOS (Keychain) ---------------------------------------------------------

def _mac_get():
    r = subprocess.run(
        ["security", "find-generic-password", "-a", ACCOUNT, "-s", SERVICE, "-w"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return None
    return r.stdout.strip()


def _mac_set(secret):
    subprocess.run(
        ["security", "add-generic-password", "-a", ACCOUNT, "-s", SERVICE, "-w", secret, "-U"],
        check=True, capture_output=True,
    )


def _mac_delete():
    subprocess.run(
        ["security", "delete-generic-password", "-a", ACCOUNT, "-s", SERVICE],
        check=True, capture_output=True,
    )


# -- Windows (Credential Manager via ctypes) ----------------------------------

def _win_get():
    import ctypes
    import ctypes.wintypes

    advapi32 = ctypes.windll.advapi32

    CRED_TYPE_GENERIC = 1

    class CREDENTIAL(ctypes.Structure):
        _fields_ = [
            ("Flags", ctypes.wintypes.DWORD),
            ("Type", ctypes.wintypes.DWORD),
            ("TargetName", ctypes.wintypes.LPWSTR),
            ("Comment", ctypes.wintypes.LPWSTR),
            ("LastWritten", ctypes.wintypes.FILETIME),
            ("CredentialBlobSize", ctypes.wintypes.DWORD),
            ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
            ("Persist", ctypes.wintypes.DWORD),
            ("AttributeCount", ctypes.wintypes.DWORD),
            ("Attributes", ctypes.c_void_p),
            ("TargetAlias", ctypes.wintypes.LPWSTR),
            ("UserName", ctypes.wintypes.LPWSTR),
        ]

    pcred = ctypes.POINTER(CREDENTIAL)()
    ok = advapi32.CredReadW(SERVICE, CRED_TYPE_GENERIC, 0, ctypes.byref(pcred))
    if not ok:
        return None
    try:
        blob = pcred.contents
        size = blob.CredentialBlobSize
        raw = ctypes.string_at(blob.CredentialBlob, size)
        return raw.decode("utf-16-le")
    finally:
        advapi32.CredFree(pcred)


def _win_set(secret):
    import ctypes
    import ctypes.wintypes

    advapi32 = ctypes.windll.advapi32

    CRED_TYPE_GENERIC = 1
    CRED_PERSIST_LOCAL_MACHINE = 2

    class CREDENTIAL(ctypes.Structure):
        _fields_ = [
            ("Flags", ctypes.wintypes.DWORD),
            ("Type", ctypes.wintypes.DWORD),
            ("TargetName", ctypes.wintypes.LPWSTR),
            ("Comment", ctypes.wintypes.LPWSTR),
            ("LastWritten", ctypes.wintypes.FILETIME),
            ("CredentialBlobSize", ctypes.wintypes.DWORD),
            ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
            ("Persist", ctypes.wintypes.DWORD),
            ("AttributeCount", ctypes.wintypes.DWORD),
            ("Attributes", ctypes.c_void_p),
            ("TargetAlias", ctypes.wintypes.LPWSTR),
            ("UserName", ctypes.wintypes.LPWSTR),
        ]

    encoded = secret.encode("utf-16-le")
    blob_array = (ctypes.c_ubyte * len(encoded))(*encoded)

    cred = CREDENTIAL()
    cred.Type = CRED_TYPE_GENERIC
    cred.TargetName = SERVICE
    cred.UserName = ACCOUNT
    cred.CredentialBlobSize = len(encoded)
    cred.CredentialBlob = blob_array
    cred.Persist = CRED_PERSIST_LOCAL_MACHINE

    ok = advapi32.CredWriteW(ctypes.byref(cred), 0)
    if not ok:
        raise OSError("CredWriteW failed")


def _win_delete():
    import ctypes

    advapi32 = ctypes.windll.advapi32

    CRED_TYPE_GENERIC = 1
    ok = advapi32.CredDeleteW(SERVICE, CRED_TYPE_GENERIC, 0)
    if not ok:
        raise OSError("CredDeleteW failed")


# -- Linux (secret-tool / libsecret) ------------------------------------------

def _has_secret_tool():
    try:
        subprocess.run(["secret-tool", "--version"], capture_output=True)
        return True
    except FileNotFoundError:
        return False


def _linux_get():
    if not _has_secret_tool():
        print("secret-tool not found. Install libsecret-tools:", file=sys.stderr)
        print("  Debian/Ubuntu: sudo apt install libsecret-tools", file=sys.stderr)
        print("  Fedora: sudo dnf install libsecret", file=sys.stderr)
        sys.exit(3)
    r = subprocess.run(
        ["secret-tool", "lookup", "service", SERVICE, "account", ACCOUNT],
        capture_output=True, text=True,
    )
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return r.stdout.strip()


def _linux_set(secret):
    if not _has_secret_tool():
        print("secret-tool not found. Install libsecret-tools:", file=sys.stderr)
        print("  Debian/Ubuntu: sudo apt install libsecret-tools", file=sys.stderr)
        print("  Fedora: sudo dnf install libsecret", file=sys.stderr)
        sys.exit(3)
    subprocess.run(
        [
            "secret-tool", "store",
            "--label", "Spotify Ads API Client Secret",
            "service", SERVICE,
            "account", ACCOUNT,
        ],
        input=secret, text=True, check=True,
    )


def _linux_delete():
    if not _has_secret_tool():
        print("secret-tool not found. Install libsecret-tools:", file=sys.stderr)
        print("  Debian/Ubuntu: sudo apt install libsecret-tools", file=sys.stderr)
        print("  Fedora: sudo dnf install libsecret", file=sys.stderr)
        sys.exit(3)
    subprocess.run(
        ["secret-tool", "clear", "service", SERVICE, "account", ACCOUNT],
        check=True,
    )


# -- Dispatch ------------------------------------------------------------------

BACKENDS = {
    "darwin": (_mac_get, _mac_set, _mac_delete),
    "win32": (_win_get, _win_set, _win_delete),
    "linux": (_linux_get, _linux_set, _linux_delete),
}


def main():
    parser = argparse.ArgumentParser(description="Cross-platform credential helper")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("get", help="Retrieve the client secret")

    sp_set = sub.add_parser("set", help="Store the client secret")
    sp_set.add_argument("--secret", required=True, help="The secret value to store")

    sub.add_parser("delete", help="Remove the client secret")

    args = parser.parse_args()

    platform = sys.platform
    if platform.startswith("linux"):
        platform = "linux"

    backend = BACKENDS.get(platform)
    if not backend:
        print(f"Unsupported platform: {sys.platform}", file=sys.stderr)
        sys.exit(2)

    get_fn, set_fn, delete_fn = backend

    try:
        if args.command == "get":
            secret = get_fn()
            if secret is None:
                sys.exit(1)
            print(secret, end="")
        elif args.command == "set":
            set_fn(args.secret)
        elif args.command == "delete":
            delete_fn()
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
