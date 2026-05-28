// <copyright file="RabbitMqConnectionProvider.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.Messaging.RabbitMq.Options;
using RabbitMQ.Client;

namespace Norge360.Messaging.RabbitMq.Connection;

public sealed class RabbitMqConnectionProvider(IOptions<RabbitMqOptions> options) : IAsyncDisposable, IDisposable
{
    private readonly SemaphoreSlim connectionLock = new(1, 1);
    private IConnection? connection;
    private bool disposed;

    public async Task<IConnection> GetConnectionAsync(CancellationToken cancellationToken)
    {
        if (connection?.IsOpen == true)
        {
            return connection;
        }

        await connectionLock.WaitAsync(cancellationToken);
        try
        {
            if (connection?.IsOpen == true)
            {
                return connection;
            }

            var rabbitOptions = options.Value;
            var factory = new ConnectionFactory
            {
                Uri = new Uri(rabbitOptions.Uri),
                AutomaticRecoveryEnabled = true,
                TopologyRecoveryEnabled = true,
                NetworkRecoveryInterval = TimeSpan.FromSeconds(rabbitOptions.NetworkRecoveryIntervalSeconds),
                ConsumerDispatchConcurrency = rabbitOptions.ConsumerDispatchConcurrency
            };

            connection?.Dispose();
            connection = await factory.CreateConnectionAsync("Norge360", cancellationToken);
            return connection;
        }
        finally
        {
            connectionLock.Release();
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        connection?.Dispose();
        connectionLock.Dispose();
        disposed = true;
    }

    public async ValueTask DisposeAsync()
    {
        if (disposed)
        {
            return;
        }

        if (connection is not null)
        {
            await connection.DisposeAsync();
        }

        connectionLock.Dispose();
        disposed = true;
    }
}
