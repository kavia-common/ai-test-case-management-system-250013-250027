# testcase_database (PostgreSQL)

This container runs a local PostgreSQL instance for the Test Case Management System.

## Ports: DB vs Preview

- **PostgreSQL server port (psql/pg client):** `5000` (configured in `startup.sh`)
- **Preview port (HTTP):** `5001` (this is **NOT** PostgreSQL; it is typically used by the DB visualizer / preview tooling)

Use the Postgres server port (`POSTGRES_PORT`, default `5000`) for backend connections.

## Connection

The authoritative connection string is written to:

- `db_connection.txt`

Example content:

```bash
psql postgresql://appuser:dbuser123@localhost:5000/myapp
```

## Environment variables (for dependent containers)

The backend should connect using the following env vars (they are also used by the included db viewer):

- `POSTGRES_URL` (optional; if present, host/port/user/password/db are read from the other vars below)
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_DB`
- `POSTGRES_PORT`

> Important: Do **not** use the preview URL/port (`5001`) for DB connections.

## Schema / migrations / seed

- Migrations: `migrations/001_init_schema.sql`
- Seed data: `seed/001_seed_data.sql`
- Convenience runner: `schema.sql` (includes both migration + seed)

To apply schema + seed manually:

```bash
# from this directory
psql "$(cat db_connection.txt)" -f schema.sql
```

## Notes for backend implementers

- Use a real password hashing algorithm (bcrypt/argon2) and store hashes in `users.password_hash`.
- The seed data uses placeholder hashes like `demo_hash_admin` intended for local/demo only.
