// <copyright file="TestLogSink.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;

namespace Norge360.Auth.TestKit.Logging;

public sealed class TestLogSink : ILoggerProvider
{
    private readonly ConcurrentQueue<TestLogEntry> _entries = new();

    public IReadOnlyCollection<TestLogEntry> Entries => _entries.ToArray();

    public ILogger CreateLogger(string categoryName) => new TestLogger(categoryName, _entries);

    public void Dispose()
    {
    }

    public bool Contains(string value) =>
        _entries.Any(entry => entry.Message.Contains(value, StringComparison.OrdinalIgnoreCase));

    private sealed class TestLogger(string categoryName, ConcurrentQueue<TestLogEntry> entries) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull =>
            NullScope.Instance;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            var message = formatter(state, exception);
            if (exception is not null)
            {
                message = $"{message}{Environment.NewLine}{exception}";
            }

            entries.Enqueue(new TestLogEntry(categoryName, logLevel, eventId, message));
        }
    }

    private sealed class NullScope : IDisposable
    {
        public static readonly NullScope Instance = new();

        public void Dispose()
        {
        }
    }
}

public sealed record TestLogEntry(string CategoryName, LogLevel Level, EventId EventId, string Message);
