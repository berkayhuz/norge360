# Development

- Docker Compose does not provision a database container.
- Configure external PostgreSQL access before starting application containers.
- Use private network reachable hostnames/IPs for PostgreSQL (`5432`).
- Set database settings via `.env`/environment variables (see `.env.example`).
- Do not commit real passwords or production connection strings.
