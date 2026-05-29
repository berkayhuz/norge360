# AWS SSM Parameter Bootstrap (Examples)

These scripts are examples only. They use placeholders and must be adapted before use.

## Important
- Do not paste real secrets into repository files.
- Use secure CI/CD or terminal input to pass secret values at execution time.
- Use `SecureString` for sensitive values.

## Files
- `create-parameters.example.ps1`
- `create-parameters.example.sh`

## Suggested process
1. Copy example script outside repository or to a secure local folder.
2. Replace placeholder variables with environment-specific values.
3. Execute with credentials from IAM role/profile with least privilege.
