"""Exercise the seeded demo through real HTTP, not direct service calls."""
from contextlib import redirect_stdout
import http.client
import io
import json
from pathlib import Path
import tempfile
import threading
import unittest

from backend.manage import seed
from backend.server import App, make_server


class DemoFlowTest(unittest.TestCase):
    def test_full_demo_over_http(self):
        with tempfile.TemporaryDirectory() as directory:
            app = App(Path(directory) / 'demo.sqlite3')
            output = io.StringIO()
            with redirect_stdout(output):
                seed(app)
            password = output.getvalue().split('Generated demo password (all three): ')[1].splitlines()[0]
            with self.assertRaises(SystemExit):
                seed(app)
            server = make_server(app, port=0)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                def call(method, path, data=None, token=None, expected=200):
                    conn = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=5)
                    headers = {'Content-Type': 'application/json'}
                    if token:
                        headers['Authorization'] = 'Bearer ' + token
                    try:
                        conn.request(method, '/api' + path,
                                     json.dumps(data) if data is not None else None, headers)
                        response = conn.getresponse()
                        body = json.loads(response.read())
                        self.assertEqual(expected, response.status, body)
                        return body
                    finally:
                        conn.close()

                a = call('POST', '/auth/login', {'email': 'alex@example.test', 'password': password})
                b = call('POST', '/auth/login', {'email': 'sam@example.test', 'password': password})
                trip = call('GET', '/trips?mine=true', token=a['token'])['items'][0]
                matches = call('GET', '/matches?trip_id=' + trip['id'], token=a['token'])['items']
                self.assertEqual([b['user']['id']], [m['owner_id'] for m in matches])
                connection = call('POST', '/connections', {'recipient_id': b['user']['id']}, a['token'], 201)
                path = '/connections/' + connection['id']
                call('POST', path + '/messages', {'body': 'before consent'}, a['token'], 403)
                call('PATCH', path, {'status': 'accepted'}, b['token'])
                message = call('POST', path + '/messages', {'body': 'See you in Tokyo!'}, a['token'], 201)
                self.assertEqual([message], call('GET', path + '/messages', token=b['token'])['items'])
                call('POST', '/blocks', {'user_id': a['user']['id']}, b['token'])
                call('POST', path + '/messages', {'body': 'blocked'}, a['token'], 403)
                call('POST', '/auth/logout', token=a['token'])
                call('GET', '/me', token=a['token'], expected=401)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)


if __name__ == '__main__':
    unittest.main()
