# Security

- Store production connection strings in secret stores (AWS SSM SecureString, vault, or equivalent).
- Never hard-code production DB credentials into appsettings files.
- Restrict PostgreSQL network access to application private IP ranges only.
- Disable sensitive data logging in production.
- Avoid logging connection strings or passwords.
- Use TLS (`SSL Mode=Require` minimum, `VerifyFull` preferred).
