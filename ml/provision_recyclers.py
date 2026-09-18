"""
One-time admin provisioning: creates a real Firebase Auth account for each
seeded, unclaimed recycler facility (phone+password, matching the app's
synthetic-email scheme), and pre-sets linked_auth_uid so the recycler only
ever needs to log in -- never self-register -- for their pre-authorized
facility. Uses the Identity Toolkit REST API directly with the project's
existing web API key (no service account key needed).
"""
import json
import random
import string
import urllib.request
import urllib.error

API_KEY = "AIzaSyDCeXojMVR3z4FaS0MB0mjjFFoKSSITrlQ"
PROJECT = "kabadiconnect"

SIGNUP_URL = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}"
FIRESTORE_BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"


def http_json(url, method="GET", body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {url} -> {e.code}: {e.read().decode()}")


def synthetic_email(e164_phone: str) -> str:
    digits = "".join(c for c in e164_phone if c.isdigit())
    return f"{digits}@phone.kabadiconnect.app"


def gen_password() -> str:
    chars = string.ascii_uppercase + string.ascii_lowercase + string.digits
    return "".join(random.choice(chars) for _ in range(10))


def firestore_value_to_py(v):
    if "stringValue" in v:
        return v["stringValue"]
    if "booleanValue" in v:
        return v["booleanValue"]
    if "nullValue" in v:
        return None
    return v


def list_recyclers():
    data = http_json(f"{FIRESTORE_BASE}/recyclers?pageSize=50")
    out = []
    for doc in data.get("documents", []):
        fields = doc.get("fields", {})
        recycler_id = doc["name"].rsplit("/", 1)[-1]
        out.append({
            "recycler_id": recycler_id,
            "name": firestore_value_to_py(fields.get("name", {})),
            "contact_phone": firestore_value_to_py(fields.get("contact_phone", {})),
            "linked_auth_uid": firestore_value_to_py(fields.get("linked_auth_uid", {})),
        })
    return out


def provision(recycler):
    email = synthetic_email(recycler["contact_phone"])
    password = gen_password()

    signup = http_json(SIGNUP_URL, method="POST", body={
        "email": email,
        "password": password,
        "returnSecureToken": True,
    })
    uid = signup["localId"]
    id_token = signup["idToken"]

    patch_url = f"{FIRESTORE_BASE}/recyclers/{recycler['recycler_id']}?updateMask.fieldPaths=linked_auth_uid"
    http_json(patch_url, method="PATCH", body={
        "fields": {"linked_auth_uid": {"stringValue": uid}}
    }, token=id_token)

    return {
        "name": recycler["name"],
        "phone_display": recycler["contact_phone"].replace("+91", ""),
        "e164_phone": recycler["contact_phone"],
        "password": password,
        "uid": uid,
    }


def main():
    recyclers = list_recyclers()
    unclaimed = [r for r in recyclers if not r["linked_auth_uid"]]
    print(f"{len(recyclers)} recyclers total, {len(unclaimed)} unclaimed -> provisioning")

    results = []
    for r in unclaimed:
        try:
            result = provision(r)
            results.append(result)
            print(f"OK  {result['name']:35} {result['phone_display']}")
        except Exception as e:
            print(f"FAIL {r['name']:35} {e}")

    with open("recycler_credentials.json", "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nwrote {len(results)} credentials -> recycler_credentials.json")


if __name__ == "__main__":
    main()
