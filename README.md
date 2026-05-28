# Norge360 Database Runtime Model

- Application server and database server run separately.
- Runtime Docker Compose starts only application services and helper services.
- No SQL Server or PostgreSQL database container is started by Compose for development/staging/production runtime.
- Applications connect to an externally hosted PostgreSQL server using environment/config based connection strings.
- Production database connection strings must be provided via environment variables or secret providers (for example AWS SSM SecureString).

## Production network model

- Public entry points: `https://norge360.com` and `https://www.norge360.com`.
- API and gateway are private-network services; they are not exposed as public domains.
- Browser API calls should use relative paths only: `/api/...`.
- Frontend server proxies `/api/*` requests to an internal upstream configured via `INTERNAL_API_GATEWAY_URL`.

## Configuration conventions

- JWT audience is domain-independent: `api://norge360`.
- Production CORS allowlist contains only:
  - `https://norge360.com`
  - `https://www.norge360.com`
- Internal service endpoints must be configured via environment variables/appsettings overrides, not hard-coded in application code.
