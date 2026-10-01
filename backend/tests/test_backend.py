import http.client
import json
from contextlib import closing
from datetime import date, timedelta
from pathlib import Path
import tempfile
import threading
import unittest

from backend.server import ApiError, App, make_server


class BackendTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'test.sqlite3'
        self.app = App(self.path)
        self.a = self.register('a')
        self.b = self.register('b')
        self.c = self.register('c', verified=False)

    def register(self, name, verified=True):
        _, auth = self.app.handle('POST', '/api/auth/register', {
            'name': name, 'email': f'{name}@example.test', 'password': 'demo-password-123', 'style': 'food'})
        if verified:
            with closing(self.app.connect()) as db, db:
                db.execute('UPDATE users SET verified=1 WHERE id=?', (auth['user']['id'],))
        return auth

    def call(self, method, path, data=None, who=None, query=None):
        return self.app.handle(method, path, data, (who or self.a)['token'], query)[1]

    def error(self, status, method, path, data=None, who=None, query=None):
        with self.assertRaises(ApiError) as caught:
            self.call(method, path, data, who, query)
        self.assertEqual(status, caught.exception.status)

    def trip(self, who=None, **changes):
        data = {'title': 'Tokyo food tour', 'country': 'Japan', 'city': 'Tokyo',
                'start': (date.today() + timedelta(days=30)).isoformat(),
                'end': (date.today() + timedelta(days=35)).isoformat(),
                'style': 'food', 'description': 'Meet for local food.'}
        data.update(changes)
        return self.call('POST', '/api/trips', data, who)

    def connection(self):
        return self.call('POST', '/api/connections', {'recipient_id': self.b['user']['id']})

    def test_registration_login_logout_and_persistence(self):
        self.error(409, 'POST', '/api/auth/register', {
            'name': 'Other', 'email': 'A@EXAMPLE.TEST', 'password': 'demo-password-123'})
        self.error(401, 'POST', '/api/auth/login', {'email': 'a@example.test', 'password': 'incorrect-password'})
        self.error(401, 'POST', '/api/auth/login', {'email': 'missing@example.test', 'password': 'incorrect-password'})
        auth = self.call('POST', '/api/auth/login', {'email': 'A@example.test', 'password': 'demo-password-123'})
        self.app = App(self.path)
        self.assertEqual('a@example.test', self.call('GET', '/api/me', who=auth)['email'])
        with closing(self.app.connect()) as db:
            user = db.execute('SELECT * FROM users WHERE id=?', (auth['user']['id'],)).fetchone()
            self.assertNotIn('demo-password-123', user['password_hash'])
            tokens = [r[0] for r in db.execute('SELECT token_hash FROM sessions')]
            self.assertNotIn(auth['token'], tokens)
        self.call('POST', '/api/auth/logout', who=auth)
        self.error(401, 'GET', '/api/me', who=auth)

    def test_profile_and_expired_sessions(self):
        profile = self.call('PATCH', '/api/me', {'name': 'Alex', 'bio': 'Hello', 'style': 'chill'})
        self.assertEqual('Alex', profile['name'])
        self.error(400, 'PATCH', '/api/me', {'verified': True})
        self.error(400, 'PATCH', '/api/me', {'style': 'unknown'})
        with closing(self.app.connect()) as db, db:
            db.execute('UPDATE sessions SET expires_at=0')
        self.error(401, 'GET', '/api/me')

    def test_trip_search_dates_styles_and_ownership(self):
        own = self.trip()
        self.trip(self.b, city='Kyoto')
        self.trip(self.c)
        rows = self.call('GET', '/api/trips', query={'country': 'japan', 'city': 'tokyo'})['items']
        self.assertEqual([own['id']], [r['id'] for r in rows])
        self.assertNotIn('email', rows[0])
        self.assertEqual([], self.call('GET', '/api/trips', query={'style': 'chill'})['items'])
        self.assertEqual([], self.call('GET', '/api/trips', query={'q': "' OR 1=1 --"})['items'])
        self.error(404, 'DELETE', '/api/trips/' + own['id'], who=self.b)
        self.call('DELETE', '/api/trips/' + own['id'])
        self.error(404, 'DELETE', '/api/trips/' + own['id'])
        self.assertEqual(1, len(self.call('GET', '/api/trips', who=self.c, query={'mine': 'true'})['items']))

    def test_trip_validation_and_pagination(self):
        for change in ({'start': '2020-01-01'}, {'end': '2020-01-01'}, {'start': 'nonsense'},
                       {'start': '2026-02-30'}, {'style': 'invalid'}, {'title': ''}):
            with self.subTest(change=change), self.assertRaises(ApiError):
                self.trip(**change)
        self.trip()
        self.trip()
        page = self.call('GET', '/api/trips', query={'limit': '1'})
        self.assertEqual(1, page['next_offset'])
        second = self.call('GET', '/api/trips', query={'limit': '1', 'offset': '1'})
        self.assertIsNone(second['next_offset'])
        self.assertNotEqual(page['items'][0]['id'], second['items'][0]['id'])
        for query in ({'limit': '0'}, {'offset': '-1'}, {'start': 'invalid'}, {'start': '2030-01-02', 'end': '2030-01-01'}):
            self.error(400, 'GET', '/api/trips', query=query)

    def test_matching_overlaps_and_style_ranking(self):
        own = self.trip()
        same = self.trip(self.b)
        different = self.trip(self.b, style='adventure')
        self.trip(self.b, city='Kyoto')
        self.trip(self.b, start=(date.today() + timedelta(days=60)).isoformat(),
                  end=(date.today() + timedelta(days=65)).isoformat())
        self.trip(self.c)
        matches = self.call('GET', '/api/matches', query={'trip_id': own['id']})['items']
        self.assertEqual([same['id'], different['id']], [r['id'] for r in matches])
        self.assertEqual([True, False], [r['same_style'] for r in matches])
        self.error(403, 'GET', '/api/matches', who=self.c, query={'trip_id': own['id']})
        self.error(404, 'GET', '/api/matches', who=self.b, query={'trip_id': own['id']})

    def test_connection_consent_messages_and_private_access(self):
        conn = self.connection()
        path = '/api/connections/' + conn['id']
        self.error(403, 'POST', path + '/messages', {'body': 'Before acceptance'})
        self.error(403, 'PATCH', path, {'status': 'accepted'})
        self.error(404, 'PATCH', path, {'status': 'accepted'}, self.c)
        self.call('PATCH', path, {'status': 'accepted'}, self.b)
        message = self.call('POST', path + '/messages', {'body': 'Meet at the station?'})
        self.app = App(self.path)
        self.assertEqual([message], self.call('GET', path + '/messages', who=self.b)['items'])
        self.assertEqual([], self.call('GET', path + '/messages', query={'after': str(message['id'])})['items'])
        self.error(404, 'GET', path + '/messages', who=self.c)
        self.error(400, 'POST', path + '/messages', {'body': ' '})
        self.error(400, 'GET', path + '/messages', query={'after': '-1'})
        self.error(409, 'POST', '/api/connections', {'recipient_id': self.a['user']['id']}, self.b)

    def test_declined_and_unverified_connections(self):
        self.error(403, 'POST', '/api/connections', {'recipient_id': self.c['user']['id']})
        self.error(400, 'POST', '/api/connections', {'recipient_id': self.a['user']['id']})
        path = '/api/connections/' + self.connection()['id']
        self.call('PATCH', path, {'status': 'declined'}, self.b)
        self.error(403, 'POST', path + '/messages', {'body': 'hello'})
        self.error(403, 'PATCH', path, {'status': 'accepted'}, self.b)

    def test_blocking_both_directions_and_reports(self):
        own = self.trip()
        self.trip(self.b)
        path = '/api/connections/' + self.connection()['id']
        self.call('PATCH', path, {'status': 'accepted'}, self.b)
        self.call('POST', '/api/blocks', {'user_id': self.b['user']['id']})
        self.assertEqual([], self.call('GET', '/api/matches', query={'trip_id': own['id']})['items'])
        for who in (self.a, self.b):
            self.error(403, 'GET', path + '/messages', who=who)
            self.error(403, 'POST', path + '/messages', {'body': 'hi'}, who)
            self.assertEqual([], self.call('GET', '/api/connections', who=who)['items'])
        report = self.call('POST', '/api/reports', {'user_id': self.b['user']['id'], 'reason': 'Unwanted messages'})
        with closing(self.app.connect()) as db:
            row = db.execute('SELECT * FROM reports WHERE id=?', (report['id'],)).fetchone()
            self.assertEqual(self.a['user']['id'], row['reporter_id'])
        self.error(404, 'GET', '/api/reports', who=self.b)

    def test_revoked_verification_disables_chat(self):
        path = '/api/connections/' + self.connection()['id']
        self.call('PATCH', path, {'status': 'accepted'}, self.b)
        with closing(self.app.connect()) as db, db:
            db.execute('UPDATE users SET verified=0 WHERE id=?', (self.b['user']['id'],))
        self.error(403, 'POST', path + '/messages', {'body': 'hello'})
        self.error(403, 'GET', path + '/messages', who=self.b)
        self.error(400, 'GET', '/api/trips', query={'offset': '99999999999999999999999'})

    def test_http_contract_cors_and_bad_payloads(self):
        server = make_server(self.app, port=0, origins=['http://localhost:5173'])
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)

        def request(method, path, body=None, headers=None):
            conn = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=5)
            try:
                conn.request(method, path, body=body, headers=headers or {})
                response = conn.getresponse()
                return response.status, dict(response.getheaders()), json.loads(response.read())
            finally:
                conn.close()

        self.assertEqual(200, request('GET', '/api/health')[0])
        status, headers, body = request('GET', '/api/me')
        self.assertEqual(401, status)
        self.assertEqual(401, body['error']['status'])
        status, headers, _ = request('OPTIONS', '/api/trips', headers={'Origin': 'http://localhost:5173'})
        self.assertEqual(200, status)
        self.assertEqual('http://localhost:5173', headers['Access-Control-Allow-Origin'])
        self.assertEqual(403, request('GET', '/api/health', headers={'Origin': 'https://unknown.test'})[0])
        for body, content_type, expected in (('{', 'application/json', 400), ('[]', 'application/json', 400),
                                               ('{}', 'text/plain', 415)):
            self.assertEqual(expected, request('POST', '/api/auth/register', body,
                                               {'Content-Type': content_type})[0])
        self.assertEqual(413, request('POST', '/api/trips', headers={'Content-Length': '65537'})[0])
        self.assertEqual(200, request('GET', '/api/me', headers={'Authorization': 'Bearer ' + self.a['token']})[0])


if __name__ == '__main__':
    unittest.main()
