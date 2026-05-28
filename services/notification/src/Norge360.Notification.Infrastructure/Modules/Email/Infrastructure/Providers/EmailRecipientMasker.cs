// <copyright file="EmailRecipientMasker.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Providers;

internal static class EmailRecipientMasker
{
    public static string Mask(string? email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            return "unknown";
        }

        var atIndex = email.IndexOf('@');
        if (atIndex <= 1 || atIndex == email.Length - 1)
        {
            return "***";
        }

        var local = email[..atIndex];
        var domain = email[(atIndex + 1)..];
        return $"{local[0]}***@{domain}";
    }
}
