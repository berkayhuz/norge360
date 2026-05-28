// <copyright file="Program.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Diagnostics.HealthChecks;
using Norge360.Configuration.AwsParameterStore;
using Norge360.Notification.Application.DependencyInjection;
using Norge360.Notification.Application.Services;
using Norge360.Notification.Infrastructure.DependencyInjection;
using Norge360.Notification.Worker;
using Norge360.Notification.Worker.Health;
using Norge360.Notification.Worker.Workers;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = Host.CreateApplicationBuilder(args);
builder.Configuration.AddNorge360AwsParameterStore(builder.Environment);

builder.Services
    .AddOptions<NotificationWorkerOptions>()
    .BindConfiguration(NotificationWorkerOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddNotificationApplication();
builder.Services.AddNotificationInfrastructure(builder.Configuration);
builder.Services.AddHostedService<NotificationQueueConsumerService>();
builder.Services.AddSingleton<NotificationWorkerMetrics>();
builder.Services.AddHealthChecks()
    .AddCheck("notification-worker-live", () => HealthCheckResult.Healthy("Notification worker process is running."), tags: ["live"])
    .AddCheck<NotificationRabbitMqHealthCheck>("notification-rabbitmq", tags: ["ready", "notification"]);

AddOpenTelemetry(builder.Services, builder.Configuration, "Norge360.Notification.Worker");

var host = builder.Build();
await host.Services.InitializeNotificationInfrastructureAsync(CancellationToken.None);
await host.RunAsync();

static void AddOpenTelemetry(IServiceCollection services, IConfiguration configuration, string serviceName)
{
    var otlpEndpoint = configuration["OpenTelemetry:Otlp:Endpoint"] ?? configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
    var telemetry = services.AddOpenTelemetry()
        .ConfigureResource(resource => resource.AddService(serviceName));

    telemetry.WithMetrics(metrics =>
    {
        metrics.AddMeter(NotificationMetrics.MeterName);
        metrics.AddMeter(NotificationWorkerMetrics.MeterName);

        if (!string.IsNullOrWhiteSpace(otlpEndpoint))
        {
            metrics.AddOtlpExporter(options => options.Endpoint = new Uri(otlpEndpoint));
        }
    });

    telemetry.WithTracing(tracing =>
    {
        tracing.AddSource("Norge360.Notification.Worker");

        if (!string.IsNullOrWhiteSpace(otlpEndpoint))
        {
            tracing.AddOtlpExporter(options => options.Endpoint = new Uri(otlpEndpoint));
        }
    });
}
