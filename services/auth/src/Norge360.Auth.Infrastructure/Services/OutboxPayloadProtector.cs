// <copyright file="OutboxPayloadProtector.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.AspNetCore.DataProtection;
using Norge360.Auth.Contracts.IntegrationEvents;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class OutboxPayloadProtector
{
    public const string ProtectedPayloadPrefix = "protected:v1:";

    private static readonly HashSet<string> SensitiveEventNames = new(StringComparer.Ordinal)
    {
        AuthEmailConfirmationRequestedV1.EventName,
        AuthPasswordResetRequestedV1.EventName,
        AuthEmailChangeRequestedV1.EventName,
        "notification.requested"
    };

    private readonly IDataProtector protector;

    public OutboxPayloadProtector(IDataProtectionProvider dataProtectionProvider)
    {
        protector = dataProtectionProvider.CreateProtector("Norge360.Auth.Outbox.Payload.v1");
    }

    public string ProtectForStorage(string eventName, string payload)
    {
        if (!SensitiveEventNames.Contains(eventName) ||
            payload.StartsWith(ProtectedPayloadPrefix, StringComparison.Ordinal))
        {
            return payload;
        }

        return ProtectedPayloadPrefix + protector.Protect(payload);
    }

    public string UnprotectForPublish(string payload)
    {
        if (!payload.StartsWith(ProtectedPayloadPrefix, StringComparison.Ordinal))
        {
            return payload;
        }

        return protector.Unprotect(payload[ProtectedPayloadPrefix.Length..]);
    }
}
