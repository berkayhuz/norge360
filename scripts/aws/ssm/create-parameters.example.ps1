param(
    [string]$EnvironmentName = "production",
    [string]$Region = "eu-central-1",
    [string]$KmsKeyId = "alias/norge360-ssm"
)

$base = "/norge360/$EnvironmentName"

Write-Host "This is an example script. Replace placeholder values at runtime."

$parameters = @(
    @{ Name = "$base/shared/database/default-connection"; Type = "SecureString"; Value = "__REPLACE_AT_RUNTIME__" },
    @{ Name = "$base/shared/redis/connection-string"; Type = "SecureString"; Value = "__REPLACE_AT_RUNTIME__" },
    @{ Name = "$base/shared/rabbitmq/connection-string"; Type = "SecureString"; Value = "__REPLACE_AT_RUNTIME__" },
    @{ Name = "$base/auth/database/connection-string"; Type = "SecureString"; Value = "__REPLACE_AT_RUNTIME__" },
    @{ Name = "$base/auth/jwt/signing-keys"; Type = "SecureString"; Value = "__REPLACE_AT_RUNTIME_JSON_ARRAY__" },
    @{ Name = "$base/auth/dataprotection/key-ring"; Type = "String"; Value = "/var/lib/norge360/auth/dataprotection" },
    @{ Name = "$base/notification/email/provider"; Type = "String"; Value = "ses" },
    @{ Name = "$base/notification/email/from-address"; Type = "String"; Value = "notifications@norge360.com" },
    @{ Name = "$base/notification/email/from-name"; Type = "String"; Value = "Norge360 Notifications" },
    @{ Name = "$base/notification/email/ses/region"; Type = "String"; Value = $Region },
    @{ Name = "$base/notification/email/ses/configuration-set"; Type = "String"; Value = "__OPTIONAL_CONFIGURATION_SET__" },
    @{ Name = "$base/notification/email/smtp/host"; Type = "SecureString"; Value = "__REPLACE_AT_RUNTIME__" },
    @{ Name = "$base/notification/email/smtp/port"; Type = "String"; Value = "587" },
    @{ Name = "$base/notification/email/smtp/username"; Type = "SecureString"; Value = "__REPLACE_AT_RUNTIME__" },
    @{ Name = "$base/notification/email/smtp/password"; Type = "SecureString"; Value = "__REPLACE_AT_RUNTIME__" }
)

foreach ($item in $parameters) {
    $arguments = @(
        "ssm", "put-parameter",
        "--region", $Region,
        "--name", $item.Name,
        "--type", $item.Type,
        "--value", $item.Value,
        "--overwrite"
    )

    if ($item.Type -eq "SecureString") {
        $arguments += @("--key-id", $KmsKeyId)
    }

    Write-Host "aws $($arguments -join ' ')"
}
