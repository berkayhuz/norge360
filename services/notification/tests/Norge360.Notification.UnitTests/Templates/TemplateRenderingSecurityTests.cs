// <copyright file="TemplateRenderingSecurityTests.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using FluentAssertions;
using Norge360.Notification.Application.Services;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Models;
using Norge360.Notification.Contracts.Notifications.Requests;

namespace Norge360.Notification.UnitTests.Templates;

public sealed class TemplateRenderingSecurityTests
{
    [Fact]
    public void Email_Templates_Should_Html_Encode_User_Controlled_Values()
    {
        var renderer = new SimpleNotificationTemplateRenderer();
        var request = new SendNotificationRequest(
            new NotificationRecipient(Guid.NewGuid(), "alice@example.com", null, null, "Alice"),
            [NotificationChannel.Email],
            NotificationCategory.Security,
            NotificationPriority.Critical,
            "Subject {{Reason}}",
            "Body {{Reason}}",
            "<p>{{Reason}}</p>",
            "account.security",
            new Dictionary<string, string>
            {
                ["Reason"] = "<script>alert('xss')</script>"
            },
            "corr-1",
            "idem-1");

        var rendered = renderer.Render(request);

        rendered.TextBody.Should().Contain("<script>alert('xss')</script>");
        rendered.HtmlBody.Should().Contain("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;");
        rendered.HtmlBody.Should().NotContain("<script>alert('xss')</script>");
    }
}
