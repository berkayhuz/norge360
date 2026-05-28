# Deployment

- Application and PostgreSQL are deployed on separate servers/services.
- Ensure PostgreSQL is pre-provisioned and reachable from the application private network.
- Allow only application server private IP/CIDR access to PostgreSQL port `5432`.
- Do not expose PostgreSQL directly to public internet.
- Keep connection strings in environment variables or secret providers.
