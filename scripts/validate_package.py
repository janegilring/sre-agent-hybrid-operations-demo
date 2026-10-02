"""Offline packaging checks; scoped binding profile, not a general secret scanner."""

import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
GUID = re.compile(r"\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b", re.I)
IPV4 = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])")
# Synthetic test identities, module identity, and published built-in role IDs.
ALLOWED_GUIDS = {
    "00000000-0000-0000-0000-000000000000",
    "11111111-1111-1111-1111-111111111111",
    "22222222-2222-2222-2222-222222222222",
    "33333333-3333-3333-3333-333333333333",
    "1ec52169-b20b-4094-9937-2adb96c98d85",
    "c046c0a1-f5ec-452e-bc35-58689380dfca",
    "acdd72a7-3385-48ef-bd42-f606fba81ae7",
    "e79298df-d852-4c6d-84f9-5d13249d1e55",
    "b24988ac-6180-42a0-ab88-20f7382dd24c",
    "749f88d5-cbae-40b8-bcfc-e573ddc772fa",
    "8e3af657-a8ff-443c-a75c-2fe8c4bcb635",
    "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    "cccccccc-cccc-cccc-cccc-cccccccccccc",
    "dddddddd-dddd-dddd-dddd-dddddddddddd",
    "984b1aee-e2db-4c89-bbb0-0ac50b7fa91c",
    "d7d7f425-620e-419c-bc75-bfe367fc8e56",
    "e5e4ef24-efc9-43c4-a4f7-0e7d2249f030",
    "11111111-1111-4111-8111-111111111111",
    "00000000-0000-4000-8000-000000000000",
    "22222222-2222-4222-8222-222222222222",
    "11fb06fb-712d-4ddd-98c7-e71bbd588830",
}
TEST_ADDRESSES = {"10.0.0.0", "10.1.0.0", "999.0.0.0"}
TEST_ADDRESS_FILES = {
    "infra/sre-agent-starter/Test-Regression.ps1",
    "scripts/validate_package.py",
}
# Documentation networks, loopback and explicit malformed/unsafe negative tests.
MCP_TEST_ADDRESSES = {
    "0.0.0.0", "0.0.0.1", "127.0.0.0", "127.0.0.1", "192.0.0.0",
    "192.0.2.004", "192.0.2.1", "192.0.2.256", "192.0.2.4", "192.000.2.4",
    "198.051.100.0", "198.51.100.0", "198.51.100.1", "198.51.100.19",
    "198.51.100.254", "198.51.100.255", "198.51.100.30", "198.51.100.31",
    "198.51.100.32", "198.51.256.0", "203.0.113.1", "203.0.113.126",
    "203.0.113.127", "203.0.113.128", "203.0.113.19", "203.0.113.2",
    "203.0.113.40", "203.0.113.64", "203.0.113.65",
    "224.0.0.0", "224.0.0.1", "240.0.0.1", "255.255.255.255",
}
MCP_TEST_FILES = {
    "tools/private-mcp/tests/BoundaryNetworkTests.cs",
    "tools/private-mcp/tests/BoundaryTests.cs",
    "tools/private-mcp/tests/ServerTests.cs",
    "scripts/validate_package.py",
}
HOSTNAME = re.compile(r"\b(?:[a-z0-9-]+\.)+[a-z]{2,}\b", re.I)
# A rejected operational hostname is represented only by its digest.
DENIED_HOST_HASHES = {
    "05fab6290805cb457e0cbeaa88c01755596b48cb80b0ee8afdf2e41145fc9aba",
}
PRIVATE_KEY = re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")


def main():
    errors = []
    names = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    ).decode().split("\0")
    names = sorted(set(filter(None, names)))
    manifest = json.loads((ROOT / "packaging/source-manifest.json").read_text(encoding="utf-8-sig"))
    allowlist = json.loads((ROOT / "packaging/export-paths.json").read_text())
    if sorted(allowlist) != sorted(entry["path"] for entry in manifest["files"]):
        errors.append("Source manifest differs from explicit export path allowlist")
    for entry in manifest["files"]:
        path = ROOT / entry["path"]
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry["exportSha256"]:
            errors.append(f"Export hash mismatch: {entry['path']}")
        if entry["sourceSha256"] != entry["exportSha256"] and path.suffix != ".md":
            errors.append(f"Non-documentation source modification: {entry['path']}")
        expected_commit = (
            "c814605a2a78f4289314bae527a8fcf16f95bbb1"
            if entry["path"].startswith("infra/hybrid-arc-connectivity/")
            else "c086d8d38f1a2d2db9242889ec715dad704749c2"
        )
        if entry.get("originCommit") != expected_commit:
            errors.append(f"Unexpected approved source revision: {entry['path']}")
    for name in names:
        path = ROOT / name
        if not path.is_file():
            errors.append(f"Missing tracked file: {name}")
            continue
        if any(part in {"bin", "obj", "__pycache__", ".local", ".azure", ".squad", "TestResults"}
               for part in path.relative_to(ROOT).parts) or ".local." in path.name:
            errors.append(f"Excluded export path: {name}")
        if name.startswith("tools/nic-sre-config/") or (
            name.startswith("tools/private-mcp/") and path.suffix in {".ps1", ".py"}
        ):
            errors.append(f"Unapproved native configuration or lab operator script: {name}")
        if name.startswith(("infra/", "tools/")) and name not in allowlist:
            errors.append(f"Unreviewed component path outside export allowlist: {name}")
        text = path.read_text(encoding="utf-8-sig")
        if PRIVATE_KEY.search(text) or any(
            hashlib.sha256(host.lower().encode()).hexdigest() in DENIED_HOST_HASHES
            for host in HOSTNAME.findall(text)
        ):
            errors.append(f"Known private binding or key marker: {name}")
        unknown = set(value.lower() for value in GUID.findall(text)) - ALLOWED_GUIDS
        if unknown:
            errors.append(f"Unallowlisted GUID: {name}")
        for value in IPV4.findall(text):
            if value == "1.0.0.0":  # ARM contentVersion, not a network binding.
                continue
            if value in TEST_ADDRESSES and name in TEST_ADDRESS_FILES:
                continue
            if value in MCP_TEST_ADDRESSES and name in MCP_TEST_FILES:
                continue
            if name == "tools/private-mcp/boundary.example.json" and value in {
                "192.0.2.4", "198.51.100.0"
            }:
                continue
            if name == "tools/private-mcp/README.md" and value in {"0.0.0.0", "224.0.0.0"}:
                continue
            errors.append(f"Unallowlisted dotted address: {name}")
        if path.suffix == ".md":
            for target in re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", text):
                if re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
                    continue
                relative = unquote(target.split("#", 1)[0])
                if relative and not (path.parent / relative).exists():
                    errors.append(f"Broken relative link: {name} -> {target}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"PASS: {len(names)} files; {len(manifest['files'])} source hashes; "
          "relative Markdown file links; scoped GUID/address/known-binding profile.")
    print("Not a general secret scan; no Azure, endpoint or native-agent acceptance implied.")


if __name__ == "__main__":
    main()
