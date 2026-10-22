"""Explicit live probe: create and revoke only our fresh FWP owner session.

Never prints or writes credentials, tokens, account payloads or response bodies.
Does not revoke any pre-existing sessions or modify profile/records.
"""
import argparse
import datetime
import json
from pathlib import Path
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', action='store_true', required=True)
    args = parser.parse_args()
    if not args.live:
        return 2
    vault = Path.home() / '.api-keys' / 'keys.env'
    values = {}
    for line in vault.read_text(encoding='utf-8-sig').splitlines():
        key, sep, value = line.partition('=')
        if sep and not key.lstrip().startswith('#'):
            values[key.strip()] = value.strip().strip('"\'')
    email = values.get('FWP_ADMIN_EMAIL')
    password = values.get('FWP_ADMIN_PASSWORD') or values.get('FWP_ADMIN_INITIAL_PASSWORD')
    if not email or not password:
        print('Required dedicated FWP owner credentials unavailable; no HTTP sent.')
        return 2
    base = 'https://fitter-welder-pro-backend-production.up.railway.app/api/fitter/account'
    token = None
    proof = {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'scope': 'fresh session only; no existing session or profile changes'}

    def request(method, endpoint, body=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        req = urllib.request.Request(base + endpoint,
            data=json.dumps(body).encode() if body is not None else None,
            headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, {}

    passed = False
    try:
        proof['anonymousReportsStatus'], _ = request('GET', '/reports')
        status, body = request('POST', '/login', {'email': email, 'password': password})
        proof['loginStatus'] = status
        token = body.get('token') if isinstance(body, dict) else None
        if status != 200 or not isinstance(token, str) or not token:
            raise RuntimeError('login failed')
        owner = body.get('account', {})
        proof['ownerMatched'] = str(owner.get('email', '')).lower() == email.lower()
        proof['adminRole'] = owner.get('role') == 'admin'
        if not proof['ownerMatched'] or not proof['adminRole']:
            raise RuntimeError('unexpected owner')
        proof['meBeforeStatus'], _ = request('GET', '/me')
        proof['adminReportsStatus'], _ = request('GET', '/reports')
        proof['logoutStatus'], _ = request('POST', '/logout', {})
        proof['meAfterStatus'], _ = request('GET', '/me')
        proof['revokedReportsStatus'], _ = request('GET', '/reports')
        passed = ((proof['meBeforeStatus'], proof['logoutStatus'], proof['meAfterStatus']) == (200, 200, 401)
                  and (proof['anonymousReportsStatus'], proof['adminReportsStatus'], proof['revokedReportsStatus']) == (401, 200, 401))
    except Exception:
        proof['probeFailed'] = True
    finally:
        if token and proof.get('meAfterStatus') != 401:
            try:
                proof['cleanupStatus'], _ = request('POST', '/logout', {})
            except Exception:
                proof['cleanupFailed'] = True
        token = None
    proof['passed'] = passed
    output = Path('build/account-logout-live-proof.json')
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(proof, indent=2), encoding='utf-8')
    print(json.dumps(proof))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
