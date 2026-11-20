#!/usr/bin/env python3
"""One-time App Store signing setup for the TestFlight build, done through the App Store Connect API.

Xcode can't sign for the team on this Mac (the team is an individual developer account, which can't
share signing access, and xcodebuild rejects the API key for automatic signing). So this script does
what Xcode would do:

  1. registers the app IDs (com.lukakaroli.flowstate, .monitor and .widgets) on the team,
  2. creates an Apple Distribution certificate, with its private key generated here and imported into
     the login keychain (a backup .p12 goes to ~/.appstoreconnect/),
  3. creates App Store provisioning profiles for both app IDs and installs them for Xcode.

Run it again when the certificate expires (once a year) or a profile goes invalid.
Credentials come from ~/.appstoreconnect/flowstate.env (see scripts/testflight.sh).

    python3 scripts/setup-signing.py
"""
import base64
import json
import os
import pathlib
import secrets
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

APP_IDS = {
    "com.lukakaroli.flowstate": ("flowstate", "flowstate App Store"),
    "com.lukakaroli.flowstate.monitor": ("flowstate monitor", "flowstate monitor App Store"),
    "com.lukakaroli.flowstate.widgets": ("flowstate widgets", "flowstate widgets App Store"),
}
HOME = pathlib.Path.home()
SECRETS = HOME / ".appstoreconnect"
PROFILE_DIRS = [
    HOME / "Library/Developer/Xcode/UserData/Provisioning Profiles",  # Xcode 16+
    HOME / "Library/MobileDevice/Provisioning Profiles",               # older Xcode
]


def load_env():
    env = {}
    for line in (SECRETS / "flowstate.env").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            env[key] = os.path.expandvars(shlex.split(value)[0])
    return env


ENV = load_env()


def token():
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
    header = b64(json.dumps({"alg": "ES256", "kid": ENV["ASC_KEY_ID"], "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64(json.dumps({"iss": ENV["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", ENV["ASC_KEY_PATH"]],
                         input=header + b"." + payload, capture_output=True, check=True).stdout
    # The JWT wants the raw r||s form of the ECDSA signature, openssl gives DER.
    parts, i = [], 2
    for _ in range(2):
        length = der[i + 1]
        parts.append(der[i + 2:i + 2 + length].lstrip(b"\0").rjust(32, b"\0"))
        i += 2 + length
    return (header + b"." + payload + b"." + b64(b"".join(parts))).decode()


def api(method, path, body=None):
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        details = json.loads(error.read() or b"{}").get("errors", [])
        sys.exit(f"✗ {method} {path} failed ({error.code}): " + "; ".join(e.get("detail", "") for e in details))


def bundle_id(identifier, name):
    found = api("GET", f"/v1/bundleIds?filter[identifier]={identifier}&limit=200")["data"]
    match = next((b for b in found if b["attributes"]["identifier"] == identifier), None)
    if match:
        print(f"• App ID {identifier} already registered")
        return match["id"]
    created = api("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": name, "platform": "IOS"}}})
    print(f"✓ Registered app ID {identifier}")
    return created["data"]["id"]


def keychain_has_identity(serial_hex):
    """Whether a certificate with this serial number has its private key in the keychain."""
    output = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True).stdout
    for line in output.splitlines():
        if "Apple Distribution" not in line or '"' not in line:
            continue
        sha1 = line.split()[1]
        pem = subprocess.run(["security", "find-certificate", "-a", "-Z", "-p", "-c", "Apple Distribution"],
                             capture_output=True, text=True).stdout
        for block in pem.split("SHA-1 hash: ")[1:]:
            if block.startswith(sha1):
                cert = block[block.index("-----BEGIN"):]
                serial = subprocess.run(["openssl", "x509", "-noout", "-serial"], input=cert,
                                        capture_output=True, text=True).stdout.strip().split("=")[-1]
                if serial.lstrip("0").upper() == serial_hex.lstrip("0").upper():
                    return True
    return False


def distribution_certificate():
    certificates = api("GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=200")["data"]
    for certificate in certificates:
        attributes = certificate["attributes"]
        if keychain_has_identity(attributes["serialNumber"]):
            print(f"• Using existing certificate {attributes['name']} (expires {attributes['expirationDate'][:10]})")
            return certificate["id"]

    print("• Creating an Apple Distribution certificate…")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", tmp / "key.pem", "-out", tmp / "request.csr", "-subj", "/CN=flowstate distribution"],
                       check=True, capture_output=True)
        csr = (tmp / "request.csr").read_text()
        created = api("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr}}})["data"]
        (tmp / "cert.der").write_bytes(base64.b64decode(created["attributes"]["certificateContent"]))
        subprocess.run(["openssl", "x509", "-inform", "DER", "-in", tmp / "cert.der", "-out", tmp / "cert.pem"], check=True)

        password = secrets.token_urlsafe(18)
        p12 = SECRETS / f"flowstate-distribution-{created['attributes']['serialNumber']}.p12"
        export = ["openssl", "pkcs12", "-export", "-inkey", tmp / "key.pem", "-in", tmp / "cert.pem",
                  "-out", p12, "-passout", f"pass:{password}", "-name", "flowstate distribution"]
        # OpenSSL 3 defaults to a p12 encryption the macOS keychain can't read.
        version = subprocess.run(["openssl", "version"], capture_output=True, text=True).stdout
        if version.startswith("OpenSSL 3"):
            export.insert(3, "-legacy")
        subprocess.run(export, check=True, capture_output=True)
        os.chmod(p12, 0o600)
        (p12.with_suffix(".password")).write_text(password + "\n")
        os.chmod(p12.with_suffix(".password"), 0o600)

        subprocess.run(["security", "import", p12, "-k", HOME / "Library/Keychains/login.keychain-db",
                        "-P", password, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], check=True)
    print(f"✓ Created {created['attributes']['name']} (expires {created['attributes']['expirationDate'][:10]}), "
          f"imported into the login keychain, backup at {p12}")
    return created["id"]


def install(profile):
    content = base64.b64decode(profile["attributes"]["profileContent"])
    uuid = profile["attributes"]["uuid"]
    for directory in PROFILE_DIRS:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{uuid}.mobileprovision").write_bytes(content)


def app_store_profile(name, bundle_resource_id, certificate_id):
    existing = api("GET", f"/v1/profiles?filter[name]={urllib.parse.quote(name)}&include=certificates&limit=200")
    for profile in existing["data"]:
        if profile["attributes"]["name"] != name:
            continue
        certificates = {c["id"] for c in profile["relationships"]["certificates"].get("data", [])}
        if profile["attributes"]["profileState"] == "ACTIVE" and certificate_id in certificates:
            install(profile)
            print(f"• Profile “{name}” already exists, installed")
            return
        api("DELETE", f"/v1/profiles/{profile['id']}")
    created = api("POST", "/v1/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
            "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
        },
    }})["data"]
    install(created)
    print(f"✓ Created and installed profile “{name}”")


# Capabilities the App Store build uses, per app ID (Sign in with Apple for study groups).
CAPABILITIES = {
    "com.lukakaroli.flowstate": {
        "APPLE_ID_AUTH": [{"key": "APPLE_ID_AUTH_APP_CONSENT", "options": [{"key": "PRIMARY_APP_CONSENT"}]}],
    },
}


def enable_capabilities(identifier, bundle_resource_id):
    """Turns on missing capabilities. Returns True if anything changed, which makes old profiles stale."""
    wanted = CAPABILITIES.get(identifier, {})
    if not wanted:
        return False
    current = api("GET", f"/v1/bundleIds/{bundle_resource_id}/bundleIdCapabilities")["data"]
    have = {c["attributes"]["capabilityType"] for c in current}
    changed = False
    for capability, settings in wanted.items():
        if capability in have:
            continue
        api("POST", "/v1/bundleIdCapabilities", {"data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": capability, "settings": settings},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}}},
        }})
        print(f"✓ Turned on {capability} for {identifier}")
        changed = True
    return changed


def delete_profiles_named(name):
    found = api("GET", f"/v1/profiles?filter[name]={urllib.parse.quote(name)}&limit=200")["data"]
    for profile in found:
        if profile["attributes"]["name"] == name:
            api("DELETE", f"/v1/profiles/{profile['id']}")


if __name__ == "__main__":
    certificate_id = distribution_certificate()
    for identifier, (app_name, profile_name) in APP_IDS.items():
        resource_id = bundle_id(identifier, app_name)
        if enable_capabilities(identifier, resource_id):
            # A profile made before the capability doesn't include it: make a new one.
            delete_profiles_named(profile_name)
        app_store_profile(profile_name, resource_id, certificate_id)
    print("Done. scripts/testflight.sh can sign and upload now.")
