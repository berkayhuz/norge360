// <copyright file="Norge360AwsParameterStoreLoader.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Amazon.SimpleSystemsManagement;
using Amazon.SimpleSystemsManagement.Model;
using Microsoft.Extensions.Logging;

namespace Norge360.Configuration.AwsParameterStore;

public sealed class Norge360AwsParameterStoreLoader(
    IAmazonSimpleSystemsManagement ssmClient,
    ILogger logger)
{
    public async Task<IReadOnlyDictionary<string, string>> LoadAsync(
        string resolvedPathPrefix,
        Norge360AwsParameterStoreOptions options,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(resolvedPathPrefix);
        ArgumentNullException.ThrowIfNull(options);

        var entries = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string? nextToken = null;
        do
        {
            var response = await ssmClient.GetParametersByPathAsync(
                new GetParametersByPathRequest
                {
                    Path = resolvedPathPrefix,
                    Recursive = options.Recursive,
                    WithDecryption = options.DecryptSecureString,
                    NextToken = nextToken,
                    MaxResults = 10
                },
                cancellationToken);

            foreach (var parameter in response.Parameters)
            {
                if (string.IsNullOrWhiteSpace(parameter.Name))
                {
                    continue;
                }

                IReadOnlyDictionary<string, string> mapped;
                try
                {
                    mapped = Norge360AwsParameterNameMapper.Map(
                        parameter.Name,
                        parameter.Value ?? string.Empty,
                        resolvedPathPrefix,
                        options.ParameterNameMappings);
                }
                catch (Exception exception)
                {
                    logger.LogError(
                        exception,
                        "Skipping AWS SSM parameter because mapping failed. ParameterName={ParameterName}",
                        parameter.Name);
                    continue;
                }

                foreach (var pair in mapped)
                {
                    entries[pair.Key] = pair.Value;
                }
            }

            nextToken = response.NextToken;
        }
        while (!string.IsNullOrWhiteSpace(nextToken));

        return entries;
    }
}
