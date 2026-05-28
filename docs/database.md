# Database

- Runtime database provider is PostgreSQL (`Npgsql.EntityFrameworkCore.PostgreSQL`).
- Connection string format:
  - `Host=DB_HOST;Port=5432;Database=DB_NAME;Username=DB_USER;Password=DB_PASSWORD;SSL Mode=Require;Trust Server Certificate=true`
- Prefer `SSL Mode=VerifyFull` in production when certificate validation is available.
- Use least-privileged runtime DB users.
- If possible, separate migration user and runtime application user.
- Keep timestamps in UTC.
- Existing SQL Server migrations require review before production migration history changes.
