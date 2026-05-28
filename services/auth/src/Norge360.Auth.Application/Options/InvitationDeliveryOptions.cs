// <copyright file="InvitationDeliveryOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Auth.Application.Options;

public sealed class InvitationDeliveryOptions
{
    public const string SectionName = "InvitationDelivery";

    public string AcceptBaseUrl { get; set; } = "https://localhost:7146";

    public string AcceptPath { get; set; } = "/invite/accept";

    public string SenderName { get; set; } = "Norge360";

    public string SenderAddress { get; set; } = "no-reply@Norge360.local";

    public bool DisableDelivery { get; set; }

    public string Provider { get; set; } = "smtp";

    public string? SmtpHost { get; set; }

    public int SmtpPort { get; set; } = 587;

    public bool SmtpUseStartTls { get; set; } = true;

    public string? SmtpUserName { get; set; }

    public string? SmtpPassword { get; set; }

    public int ResendThrottleSeconds { get; set; } = 60;

    public int MaxResends { get; set; } = 5;

    public string BuildAcceptUrl(Guid tenantId, string token, string email)
    {
        var baseUrl = AcceptBaseUrl.TrimEnd('/');
        var path = AcceptPath.StartsWith('/') ? AcceptPath : "/" + AcceptPath;
        var query = $"tenantId={Uri.EscapeDataString(tenantId.ToString("D"))}&token={Uri.EscapeDataString(token)}&email={Uri.EscapeDataString(email)}";
        return $"{baseUrl}{path}?{query}";
    }
}
