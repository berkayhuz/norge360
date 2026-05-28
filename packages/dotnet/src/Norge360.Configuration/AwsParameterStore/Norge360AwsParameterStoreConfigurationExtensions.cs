// <copyright file="Norge360AwsParameterStoreConfigurationExtensions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Amazon;
using Amazon.SimpleSystemsManagement;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace Norge360.Configuration.AwsParameterStore;

public static class Norge360AwsParameterStoreConfigurationExtensions
{
    public static ConfigurationManager AddNorge360AwsParameterStore(
        this ConfigurationManager configuration,
        IHostEnvironment environment,
        Action<Norge360AwsParameterStoreOptions>? configure = null,
        ILoggerFactory? loggerFactory = null,
        Func<AmazonSimpleSystemsManagementConfig, IAmazonSimpleSystemsManagement>? clientFactory = null)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);

        var logger = loggerFactory?.CreateLogger("Norge360.Configuration.AwsParameterStore")
            ?? NullLogger.Instance;

        var options = configuration.GetSection(Norge360AwsParameterStoreOptions.SectionName).Get<Norge360AwsParameterStoreOptions>()
            ?? new Norge360AwsParameterStoreOptions();
        configure?.Invoke(options);

        if (!options.Enabled)
        {
            if (environment.IsProduction() && options.RequireInProduction)
            {
                throw new InvalidOperationException(
                    $"{Norge360AwsParameterStoreOptions.SectionName}:Enabled must be true in production.");
            }

            logger.LogInformation("AWS SSM parameter store integration is disabled.");
            return configuration;
        }

        if (options.ReloadOnChange)
        {
            logger.LogWarning(
                "AWS SSM reload-on-change is requested but not enabled in this implementation. Configuration will be loaded once at startup.");
        }

        var pathPrefix = ResolvePathPrefix(options.ParameterPathPrefix, environment.EnvironmentName);

        var clientConfig = new AmazonSimpleSystemsManagementConfig();
        if (!string.IsNullOrWhiteSpace(options.Region))
        {
            clientConfig.RegionEndpoint = RegionEndpoint.GetBySystemName(options.Region);
        }

        try
        {
            using var ssmClient = clientFactory?.Invoke(clientConfig)
                ?? new AmazonSimpleSystemsManagementClient(clientConfig);
            var loader = new Norge360AwsParameterStoreLoader(ssmClient, logger);
            var entries = loader.LoadAsync(pathPrefix, options, CancellationToken.None).GetAwaiter().GetResult();
            if (entries.Count == 0 && !options.OptionalWhenEnabled)
            {
                throw new InvalidOperationException(
                    $"AWS SSM returned no parameters for path '{pathPrefix}' while integration is enabled.");
            }

            var normalizedEntries = entries.ToDictionary(
                pair => pair.Key,
                pair => (string?)pair.Value,
                StringComparer.OrdinalIgnoreCase);
            configuration.AddInMemoryCollection(normalizedEntries);
            ValidateRequiredKeys(configuration, options, pathPrefix, environment);
            logger.LogInformation(
                "AWS SSM parameters loaded for path {PathPrefix}. LoadedEntries={LoadedEntries}",
                pathPrefix,
                entries.Count);
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "AWS SSM parameter store load failed for path {PathPrefix}.",
                pathPrefix);

            if (environment.IsProduction() || !options.OptionalWhenEnabled)
            {
                throw;
            }
        }

        return configuration;
    }

    private static void ValidateRequiredKeys(
        IConfiguration configuration,
        Norge360AwsParameterStoreOptions options,
        string pathPrefix,
        IHostEnvironment environment)
    {
        if (options.RequiredConfigurationKeys.Count == 0)
        {
            return;
        }

        var missingKeys = options.RequiredConfigurationKeys
            .Where(key => string.IsNullOrWhiteSpace(configuration[key]))
            .ToArray();
        if (missingKeys.Length == 0)
        {
            return;
        }

        if (environment.IsProduction() || options.RequireInProduction)
        {
            throw new InvalidOperationException(
                $"AWS SSM path '{pathPrefix}' is missing required configuration keys: {string.Join(", ", missingKeys)}");
        }
    }

    private static string ResolvePathPrefix(string rawPrefix, string environmentName)
    {
        var normalizedEnvironment = string.IsNullOrWhiteSpace(environmentName)
            ? "production"
            : environmentName.Trim().ToLowerInvariant();
        var resolvedPrefix = rawPrefix.Replace("{environment}", normalizedEnvironment, StringComparison.OrdinalIgnoreCase);
        return resolvedPrefix.EndsWith("/", StringComparison.Ordinal)
            ? resolvedPrefix.TrimEnd('/')
            : resolvedPrefix;
    }
}
