// <copyright file="RabbitMqOptionsValidation.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;

namespace Norge360.Messaging.RabbitMq.Options;

public sealed class RabbitMqOptionsValidation(IHostEnvironment environment) : IValidateOptions<RabbitMqOptions>
{
    private static readonly string[] UnsafeProductionMarkers = ["REPLACE", "CHANGE_ME", "LOCAL", "DEV", "TEST", "CHANGETHIS"];

    public ValidateOptionsResult Validate(string? name, RabbitMqOptions options)
    {
        var failures = new List<string>();

        if (!Uri.TryCreate(options.Uri, UriKind.Absolute, out var uri) || uri.Scheme is not ("amqp" or "amqps"))
        {
            failures.Add("Messaging:RabbitMq:Uri must be an absolute amqp or amqps URI.");
        }
        else if (environment.IsProduction())
        {
            ValidateProductionUri(uri, failures);
        }

        if (string.IsNullOrWhiteSpace(options.Exchange))
        {
            failures.Add("Messaging:RabbitMq:Exchange is required.");
        }
        else if (environment.IsProduction() &&
                 UnsafeProductionMarkers.Any(marker => options.Exchange.Contains(marker, StringComparison.OrdinalIgnoreCase)))
        {
            failures.Add("Messaging:RabbitMq:Exchange contains a non-production marker.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }

    private static void ValidateProductionUri(Uri uri, List<string> failures)
    {
        if (uri.Scheme != "amqps")
        {
            failures.Add("Messaging:RabbitMq:Uri must use amqps in production.");
        }

        if (uri.IsLoopback)
        {
            failures.Add("Messaging:RabbitMq:Uri cannot point to localhost in production.");
        }

        if (uri.UserInfo.Contains("guest", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("Messaging:RabbitMq:Uri cannot use the guest account in production.");
        }

        if (string.IsNullOrWhiteSpace(uri.UserInfo))
        {
            failures.Add("Messaging:RabbitMq:Uri must include production broker credentials.");
        }

        if (UnsafeProductionMarkers.Any(marker => uri.UserInfo.Contains(marker, StringComparison.OrdinalIgnoreCase)))
        {
            failures.Add("Messaging:RabbitMq:Uri contains a non-production credential marker.");
        }
    }
}
