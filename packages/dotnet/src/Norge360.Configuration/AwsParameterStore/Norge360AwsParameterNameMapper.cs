// <copyright file="Norge360AwsParameterNameMapper.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;

namespace Norge360.Configuration.AwsParameterStore;

public static class Norge360AwsParameterNameMapper
{
    private static readonly IReadOnlyDictionary<string, string[]> KnownMappings =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["shared/database/default-connection"] = ["ConnectionStrings:DefaultConnection"],
            ["shared/redis/connection-string"] = ["Infrastructure:DistributedCache:RedisConnectionString"],
            ["shared/rabbitmq/connection-string"] = ["Messaging:RabbitMq:Uri"],
            ["auth/database/connection-string"] = ["ConnectionStrings:IdentityConnection"],
            ["auth/dataprotection/key-ring"] = ["Infrastructure:DataProtection:KeyRingPath"],
            ["notification/email/provider"] = ["Notification:Email:Provider"],
            ["notification/email/from-address"] = ["Notification:Email:Smtp:FromAddress", "Notification:Email:AmazonSes:FromAddress"],
            ["notification/email/from-name"] = ["Notification:Email:Smtp:FromName", "Notification:Email:AmazonSes:FromName"],
            ["notification/email/ses/region"] = ["Notification:Email:AmazonSes:Region"],
            ["notification/email/ses/configuration-set"] = ["Notification:Email:AmazonSes:ConfigurationSetName"],
            ["notification/email/smtp/host"] = ["Notification:Email:Smtp:Host"],
            ["notification/email/smtp/port"] = ["Notification:Email:Smtp:Port"],
            ["notification/email/smtp/username"] = ["Notification:Email:Smtp:UserName"],
            ["notification/email/smtp/password"] = ["Notification:Email:Smtp:Password"]
        };

    public static IReadOnlyDictionary<string, string> Map(
        string parameterName,
        string parameterValue,
        string resolvedPathPrefix,
        IReadOnlyDictionary<string, string>? explicitMappings = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(parameterName);
        ArgumentNullException.ThrowIfNull(parameterValue);
        ArgumentException.ThrowIfNullOrWhiteSpace(resolvedPathPrefix);

        var normalizedPrefix = NormalizePrefix(resolvedPathPrefix);
        var normalizedName = NormalizeName(parameterName);
        if (!normalizedName.StartsWith(normalizedPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }

        var relativeName = normalizedName[normalizedPrefix.Length..].TrimStart('/');
        if (string.IsNullOrWhiteSpace(relativeName))
        {
            return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }

        if (TryMapExplicit(relativeName, parameterValue, explicitMappings, out var explicitResult))
        {
            return explicitResult;
        }

        if (TryMapSigningKeys(relativeName, parameterValue, out var signingKeyResult))
        {
            return signingKeyResult;
        }

        if (KnownMappings.TryGetValue(relativeName, out var mappedKeys))
        {
            return mappedKeys.ToDictionary(key => key, _ => parameterValue, StringComparer.OrdinalIgnoreCase);
        }

        return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            [ToConfigurationKey(relativeName)] = parameterValue
        };
    }

    private static bool TryMapExplicit(
        string relativeName,
        string parameterValue,
        IReadOnlyDictionary<string, string>? explicitMappings,
        out IReadOnlyDictionary<string, string> mapped)
    {
        if (explicitMappings is not null && explicitMappings.TryGetValue(relativeName, out var mappedKey))
        {
            mapped = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                [mappedKey] = parameterValue
            };
            return true;
        }

        mapped = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        return false;
    }

    private static bool TryMapSigningKeys(
        string relativeName,
        string parameterValue,
        out IReadOnlyDictionary<string, string> mapped)
    {
        if (!string.Equals(relativeName, "auth/jwt/signing-keys", StringComparison.OrdinalIgnoreCase))
        {
            mapped = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            return false;
        }

        using var json = JsonDocument.Parse(parameterValue);
        if (json.RootElement.ValueKind is not JsonValueKind.Array and not JsonValueKind.Object)
        {
            throw new InvalidOperationException(
                "SSM parameter 'auth/jwt/signing-keys' must be a JSON array or object.");
        }

        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        FlattenJson("Jwt:SigningKeys", json.RootElement, result);
        mapped = result;
        return true;
    }

    private static void FlattenJson(
        string prefix,
        JsonElement element,
        IDictionary<string, string> destination)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                foreach (var property in element.EnumerateObject())
                {
                    FlattenJson($"{prefix}:{property.Name}", property.Value, destination);
                }

                break;

            case JsonValueKind.Array:
                var index = 0;
                foreach (var item in element.EnumerateArray())
                {
                    FlattenJson($"{prefix}:{index}", item, destination);
                    index++;
                }

                break;

            case JsonValueKind.String:
                destination[prefix] = element.GetString() ?? string.Empty;
                break;

            case JsonValueKind.True:
            case JsonValueKind.False:
            case JsonValueKind.Number:
                destination[prefix] = element.ToString();
                break;

            case JsonValueKind.Null:
                destination[prefix] = string.Empty;
                break;
        }
    }

    private static string ToConfigurationKey(string relativeName)
    {
        var segments = relativeName
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(ToPascalSegment);
        return string.Join(':', segments);
    }

    private static string ToPascalSegment(string value)
    {
        var parts = value.Split('-', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return value;
        }

        return string.Concat(parts.Select(part =>
            part.Length == 0 ? part : char.ToUpperInvariant(part[0]) + part[1..]));
    }

    private static string NormalizePrefix(string pathPrefix) => NormalizeName(pathPrefix).TrimEnd('/');

    private static string NormalizeName(string name) => name.Replace('\\', '/').Trim();
}
