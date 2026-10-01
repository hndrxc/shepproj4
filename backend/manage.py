"""Backend operator tools. Run from the repository root with python3 -m backend.manage."""
import argparse
from contextlib import closing
from datetime import date, timedelta
import secrets

from backend.server import App


def seed(app):
    """Create synthetic demo travelers in a NEW database, never real verified identities."""
    with closing(app.connect()) as db:
        if db.execute('SELECT 1 FROM users LIMIT 1').fetchone():
            raise SystemExit('Demo seed requires an empty database; choose a separate --database path.')
    password = secrets.token_urlsafe(18)
    for name, email, style, city in (
        ('Demo Alex', 'alex@example.test', 'food', 'Tokyo'),
        ('Demo Sam', 'sam@example.test', 'food', 'Tokyo'),
        ('Demo Jordan', 'jordan@example.test', 'adventure', 'Kyoto'),
    ):
        _, auth = app.handle('POST', '/api/auth/register', {
            'email': email, 'password': password, 'name': name, 'style': style})
        with closing(app.connect()) as db, db:
            db.execute('UPDATE users SET verified=1 WHERE id=?', (auth['user']['id'],))
        app.handle('POST', '/api/trips', {
            'title': f'Demo: explore {city}', 'country': 'Japan', 'city': city,
            'start': (date.today() + timedelta(days=30)).isoformat(),
            'end': (date.today() + timedelta(days=37)).isoformat(), 'style': style,
            'description': 'Synthetic sample trip for the classroom demo.'}, token=auth['token'])
        app.handle('POST', '/api/auth/logout', token=auth['token'])
    print('Synthetic demo users: alex@example.test, sam@example.test, jordan@example.test')
    print(f'Generated demo password (all three): {password}')
    print('Demo verification flags are fixtures, not evidence of identity checks.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', default='backend/data/roam.sqlite3')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('seed-demo', help='Seed an EMPTY, demo-only database with synthetic users')
    verify = commands.add_parser('verify', help='Record verification after an external/manual identity check')
    verify.add_argument('--email', required=True)
    verify.add_argument('--confirmed-external-check', action='store_true', required=True)
    revoke = commands.add_parser('revoke-verification')
    revoke.add_argument('--email', required=True)
    commands.add_parser('reports', help='Read reports locally for manual moderation')
    args = parser.parse_args()
    app = App(args.database)
    if args.command == 'seed-demo':
        seed(app)
        return
    with closing(app.connect()) as db, db:
        if args.command == 'reports':
            import json
            for row in db.execute('SELECT * FROM reports ORDER BY created_at'):
                print(json.dumps(dict(row)))
            return
        result = db.execute('UPDATE users SET verified=? WHERE email=?',
                            (int(args.command == 'verify'), args.email.strip().lower()))
        if not result.rowcount:
            raise SystemExit('No such user')
        print('Verification status updated.')


if __name__ == '__main__':
    main()
