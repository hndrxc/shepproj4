"""Local/demo JSON API using Python 3.12+ and SQLite; no pip dependencies."""

import argparse
import hashlib
import hmac
import json
import logging
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
from contextlib import closing
from datetime import date, datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

STYLES = ('solo', 'chill', 'adventure', 'luxury', 'budget', 'food')
SESSION_SECONDS = 7 * 24 * 60 * 60


class ApiError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def now():
    return datetime.now(timezone.utc).isoformat()


def identifier():
    return secrets.token_hex(16)


def text(data, key, maximum=200, default=None):
    value = data.get(key, default)
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise ApiError(400, f'{key} must be non-empty text of at most {maximum} characters')
    return value.strip()


def choice(data, key, choices):
    value = text(data, key)
    if value not in choices:
        raise ApiError(400, f'{key} must be one of: {", ".join(choices)}')
    return value


def parse_date(value):
    try:
        if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
            raise ValueError()
        return date.fromisoformat(value)
    except ValueError:
        raise ApiError(400, 'Dates must use YYYY-MM-DD') from None


def password_hash(password, salt=None):
    salt = salt or secrets.token_hex(16)
    digest = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex()
    return f'{salt}:{digest}'


def public_user(row):
    return {key: (bool(row[key]) if key == 'verified' else row[key])
            for key in ('id', 'name', 'bio', 'style', 'verified')}


class App:
    def __init__(self, database):
        self.database = str(database)
        Path(database).parent.mkdir(parents=True, exist_ok=True)
        with closing(self.connect()) as db:
            db.executescript(Path(__file__).with_name('schema.sql').read_text())
            db.execute('PRAGMA journal_mode=WAL')

    def connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        return db

    def session(self, db, user):
        token = secrets.token_urlsafe(32)
        expires = int(time.time()) + SESSION_SECONDS
        db.execute('DELETE FROM sessions WHERE expires_at <= ?', (int(time.time()),))
        db.execute('INSERT INTO sessions VALUES (?,?,?)',
                   (hashlib.sha256(token.encode()).hexdigest(), user['id'], expires))
        return {'token': token, 'expires_at': expires, 'user': {**public_user(user), 'email': user['email']}}

    def authenticate(self, db, token):
        user = db.execute('SELECT u.* FROM users u JOIN sessions s ON s.user_id=u.id '
                          'WHERE s.token_hash=? AND s.expires_at>?',
                          (hashlib.sha256(token.encode()).hexdigest(), int(time.time()))).fetchone()
        if user is None:
            raise ApiError(401, 'A valid Bearer token is required')
        return user

    def blocked(self, db, first, second):
        return db.execute('SELECT 1 FROM blocks WHERE (user_id=? AND blocked_id=?) '
                          'OR (user_id=? AND blocked_id=?)',
                          (first, second, second, first)).fetchone() is not None

    def other_user(self, db, uid, other):
        row = db.execute('SELECT * FROM users WHERE id=?', (other,)).fetchone()
        if row is None:
            raise ApiError(404, 'Traveler not found')
        if other == uid:
            raise ApiError(400, 'Choose another traveler')
        return row

    def page(self, query):
        try:
            limit, offset = int(query.get('limit', '20')), int(query.get('offset', '0'))
            if not 1 <= limit <= 100 or not 0 <= offset <= 1000000000:
                raise ValueError()
            return limit, offset
        except (ValueError, TypeError):
            raise ApiError(400, 'limit must be 1-100 and offset must be between 0 and 1000000000') from None

    def handle(self, method, path, data=None, token='', query=None):
        data, query = data if data is not None else {}, query or {}
        if not isinstance(data, dict):
            raise ApiError(400, 'JSON body must be an object')
        with closing(self.connect()) as db, db:
            return self.dispatch(db, method, path.rstrip('/'), data, token, query)

    def dispatch(self, db, method, path, data, token, query):
        if method == 'GET' and path == '/api/health':
            return 200, {'status': 'ok'}
        if method == 'GET' and path == '/api/styles':
            return 200, {'items': list(STYLES)}
        if method == 'POST' and path in ('/api/auth/register', '/api/auth/login'):
            email = text(data, 'email', 254).lower()
            if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email):
                raise ApiError(400, 'A valid email address is required')
            password = data.get('password')
            if not isinstance(password, str) or not 12 <= len(password) <= 128:
                raise ApiError(400, 'password must contain 12-128 characters')
            if path.endswith('/register'):
                name = text(data, 'name', 80)
                style = choice({'style': data.get('style', 'solo')}, 'style', STYLES)
                try:
                    db.execute('INSERT INTO users(id,email,password_hash,name,style,created_at) VALUES(?,?,?,?,?,?)',
                               (identifier(), email, password_hash(password), name, style, now()))
                except sqlite3.IntegrityError:
                    raise ApiError(409, 'Email is already registered') from None
            user = db.execute('SELECT * FROM users WHERE email=?', (email,)).fetchone()
            # Run the same expensive hash for unknown emails to reduce timing leakage.
            stored = user['password_hash'] if user else ('00' * 16 + ':' + '00' * 64)
            actual = password_hash(password, stored.split(':')[0])
            if not hmac.compare_digest(actual, stored):
                raise ApiError(401, 'Invalid email or password')
            return (201 if path.endswith('/register') else 200), self.session(db, user)

        user = self.authenticate(db, token)
        uid = user['id']
        if method == 'POST' and path == '/api/auth/logout':
            db.execute('DELETE FROM sessions WHERE token_hash=?', (hashlib.sha256(token.encode()).hexdigest(),))
            return 200, {'logged_out': True}
        if path == '/api/me' and method in ('GET', 'PATCH'):
            if method == 'PATCH':
                if set(data) - {'name', 'bio', 'style'}:
                    raise ApiError(400, 'Only name, bio, and style may be updated')
                name = text(data, 'name', 80, user['name'])
                bio = data.get('bio', user['bio'])
                if not isinstance(bio, str) or len(bio) > 1000:
                    raise ApiError(400, 'bio must be text of at most 1000 characters')
                style = choice({'style': data.get('style', user['style'])}, 'style', STYLES)
                db.execute('UPDATE users SET name=?,bio=?,style=? WHERE id=?', (name, bio.strip(), style, uid))
                user = db.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone()
            return 200, {**public_user(user), 'email': user['email']}

        if path == '/api/trips' and method == 'POST':
            start, end = parse_date(data.get('start')), parse_date(data.get('end'))
            if start < date.today() or end < start:
                raise ApiError(400, 'Trip dates must be today or later and end on or after start')
            trip_id = identifier()
            db.execute('INSERT INTO trips VALUES(?,?,?,?,?,?,?,?,?,?)',
                       (trip_id, uid, text(data, 'title', 120), text(data, 'country', 80),
                        text(data, 'city', 80), start.isoformat(), end.isoformat(),
                        choice(data, 'style', STYLES), text(data, 'description', 2000, 'Let us travel together.'), now()))
            return 201, dict(db.execute('SELECT * FROM trips WHERE id=?', (trip_id,)).fetchone())

        if method == 'GET' and path in ('/api/trips', '/api/matches'):
            limit, offset = self.page(query)
            clauses, args = [], []
            if path == '/api/matches':
                if not user['verified']:
                    raise ApiError(403, 'Verification is required to discover matches')
                own = db.execute('SELECT * FROM trips WHERE id=? AND owner_id=?', (query.get('trip_id', ''), uid)).fetchone()
                if own is None:
                    raise ApiError(404, 'Your trip was not found; supply trip_id')
                clauses += ['t.owner_id != ?', 'u.verified=1', 't.country=? COLLATE NOCASE',
                            't.city=? COLLATE NOCASE', 't.start<=?', 't.end>=?']
                args += [uid, own['country'], own['city'], own['end'], own['start']]
            elif query.get('mine') == 'true':
                clauses += ['t.owner_id=?']
                args += [uid]
            else:
                clauses += ['u.verified=1']
            clauses += ['NOT EXISTS (SELECT 1 FROM blocks b WHERE '
                        '(b.user_id=? AND b.blocked_id=t.owner_id) OR '
                        '(b.blocked_id=? AND b.user_id=t.owner_id))']
            args += [uid, uid]
            for key in ('country', 'city', 'style'):
                if query.get(key):
                    if key == 'style':
                        choice(query, 'style', STYLES)
                    clauses.append(f't.{key}=? COLLATE NOCASE')
                    args.append(query[key])
            if query.get('start') and query.get('end'):
                if parse_date(query['end']) < parse_date(query['start']):
                    raise ApiError(400, 'end must be on or after start')
            for key, column, op in (('start', 'end', '>='), ('end', 'start', '<=')):
                if query.get(key):
                    clauses.append(f't.{column}{op}?')
                    args.append(parse_date(query[key]).isoformat())
            if query.get('q'):
                clauses.append('(instr(lower(t.title || t.country || t.city || u.name), lower(?))>0)')
                args.append(text(query, 'q', 120))
            clauses.append('t.end>=?')
            args.append(date.today().isoformat())
            order = 't.start,t.id'
            if path == '/api/matches':
                order = 'CASE WHEN t.style=? THEN 0 ELSE 1 END,t.start,t.id'
                args.append(own['style'])
            rows = db.execute('SELECT t.*,u.name AS owner_name,u.verified FROM trips t '
                              'JOIN users u ON u.id=t.owner_id WHERE ' + ' AND '.join(clauses) +
                              ' ORDER BY ' + order + ' LIMIT ? OFFSET ?', (*args, limit + 1, offset)).fetchall()
            items = [dict(row) for row in rows[:limit]]
            for item in items:
                item['verified'] = bool(item['verified'])
                if path == '/api/matches':
                    item['same_style'] = item['style'] == own['style']
            return 200, {'items': items, 'next_offset': offset + limit if len(rows) > limit else None}

        if re.fullmatch(r'/api/trips/[a-f0-9]{32}', path) and method == 'DELETE':
            result = db.execute('DELETE FROM trips WHERE id=? AND owner_id=?', (path.split('/')[-1], uid))
            if not result.rowcount:
                raise ApiError(404, 'Your trip was not found')
            return 200, {'deleted': True}

        if path == '/api/connections' and method == 'POST':
            other = self.other_user(db, uid, text(data, 'recipient_id', 32))
            if not user['verified'] or not other['verified'] or self.blocked(db, uid, other['id']):
                raise ApiError(403, 'Both travelers must be verified and not blocked')
            cid = identifier()
            try:
                db.execute('INSERT INTO connections VALUES(?,?,?,?,?)', (cid, uid, other['id'], 'pending', now()))
            except sqlite3.IntegrityError:
                raise ApiError(409, 'A connection already exists between these travelers') from None
            return 201, dict(db.execute('SELECT * FROM connections WHERE id=?', (cid,)).fetchone())

        if path == '/api/connections' and method == 'GET':
            limit, offset = self.page(query)
            rows = db.execute('SELECT * FROM connections c WHERE (sender_id=? OR recipient_id=?) '
                              'AND NOT EXISTS (SELECT 1 FROM blocks b WHERE '
                              '(b.user_id=c.sender_id AND b.blocked_id=c.recipient_id) OR '
                              '(b.user_id=c.recipient_id AND b.blocked_id=c.sender_id)) '
                              'ORDER BY created_at,id LIMIT ? OFFSET ?', (uid, uid, limit + 1, offset)).fetchall()
            return 200, {'items': [dict(r) for r in rows[:limit]],
                         'next_offset': offset + limit if len(rows) > limit else None}

        match = re.fullmatch(r'/api/connections/([a-f0-9]{32})(/messages)?', path)
        if match:
            cid, messages = match.groups()
            connection = db.execute('SELECT * FROM connections WHERE id=? AND (sender_id=? OR recipient_id=?)',
                                    (cid, uid, uid)).fetchone()
            if connection is None:
                raise ApiError(404, 'Connection not found')
            verified_count = db.execute(
                'SELECT count(*) FROM users WHERE id IN (?,?) AND verified=1',
                (connection['sender_id'], connection['recipient_id'])).fetchone()[0]
            if verified_count != 2:
                raise ApiError(403, 'Both travelers must remain verified')
            if self.blocked(db, connection['sender_id'], connection['recipient_id']):
                raise ApiError(403, 'Connection is blocked')
            if not messages and method == 'PATCH':
                if connection['recipient_id'] != uid or connection['status'] != 'pending':
                    raise ApiError(403, 'Only the recipient may respond to a pending connection')
                status = choice(data, 'status', ('accepted', 'declined'))
                db.execute('UPDATE connections SET status=? WHERE id=?', (status, cid))
                return 200, {**dict(connection), 'status': status}
            if messages and method in ('GET', 'POST'):
                if connection['status'] != 'accepted':
                    raise ApiError(403, 'Accept the connection before messaging')
                if method == 'POST':
                    cursor = db.execute('INSERT INTO messages(connection_id,sender_id,body,created_at) VALUES(?,?,?,?)',
                                        (cid, uid, text(data, 'body', 4000), now()))
                    return 201, dict(db.execute('SELECT * FROM messages WHERE id=?', (cursor.lastrowid,)).fetchone())
                limit, _ = self.page(query)
                try:
                    after = int(query.get('after', '0'))
                    if not 0 <= after <= 9223372036854775807:
                        raise ValueError()
                except (TypeError, ValueError):
                    raise ApiError(400, 'after must be a non-negative 64-bit message ID') from None
                rows = db.execute('SELECT * FROM messages WHERE connection_id=? AND id>? ORDER BY id LIMIT ?',
                                  (cid, after, limit)).fetchall()
                return 200, {'items': [dict(r) for r in rows], 'next_after': rows[-1]['id'] if rows else after}

        if path in ('/api/blocks', '/api/reports') and method == 'POST':
            other = text(data, 'user_id', 32)
            self.other_user(db, uid, other)
            if path == '/api/blocks':
                db.execute('INSERT OR IGNORE INTO blocks VALUES(?,?)', (uid, other))
                return 200, {'blocked': True}
            report_id = identifier()
            db.execute('INSERT INTO reports VALUES(?,?,?,?,?)',
                       (report_id, uid, other, text(data, 'reason', 2000), now()))
            return 201, {'id': report_id, 'status': 'received'}
        raise ApiError(404, 'Endpoint not found')


def make_server(app, host='127.0.0.1', port=8080, origins=()):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # Do not log tokens, chat content, or query strings.

        def send_json(self, status, payload):
            encoded = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(encoded)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Vary', 'Origin')
            if self.headers.get('Origin') in origins:
                self.send_header('Access-Control-Allow-Origin', self.headers['Origin'])
                self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
                self.send_header('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS')
            self.end_headers()
            self.wfile.write(encoded)

        def request(self):
            self.close_connection = True
            try:
                origin = self.headers.get('Origin')
                if origin and origin not in origins:
                    raise ApiError(403, 'Origin is not allowed')
                if self.command == 'OPTIONS':
                    return self.send_json(200, {})
                if self.headers.get('Transfer-Encoding'):
                    raise ApiError(400, 'Transfer-Encoding is not supported')
                try:
                    length = int(self.headers.get('Content-Length', '0'))
                except ValueError:
                    raise ApiError(400, 'Invalid Content-Length') from None
                if not 0 <= length <= 65536:
                    raise ApiError(413, 'Request body exceeds 64 KiB')
                data = {}
                if length:
                    if self.headers.get_content_type() != 'application/json':
                        raise ApiError(415, 'Use application/json')
                    try:
                        data = json.loads(self.rfile.read(length))
                    except (ValueError, UnicodeDecodeError):
                        raise ApiError(400, 'Malformed JSON') from None
                url = urlsplit(self.path)
                query = {k: v[-1] for k, v in parse_qs(url.query).items()}
                auth = self.headers.get('Authorization', '')
                token = auth[7:] if auth.startswith('Bearer ') else ''
                status, body = app.handle(self.command, url.path, data, token, query)
                self.send_json(status, body)
            except ApiError as error:
                self.send_json(error.status, {'error': {'status': error.status, 'message': error.message}})
            except Exception:
                logging.exception('API request failed')
                self.send_json(500, {'error': {'status': 500, 'message': 'Internal server error'}})

        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        do_GET = do_POST = do_PATCH = do_DELETE = do_OPTIONS = request

    return ThreadingHTTPServer((host, port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', default=os.environ.get('ROAM_DATABASE', 'backend/data/roam.sqlite3'))
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--origin', action='append', default=[], help='Allowed browser origin; repeatable')
    args = parser.parse_args()
    app = App(args.database)
    server = make_server(app, args.host, args.port, args.origin)
    print(f'Roam Together API listening on http://{args.host}:{args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
