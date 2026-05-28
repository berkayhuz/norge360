// <copyright file="FakeClock.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Clock;

namespace Norge360.Auth.TestKit.Fakes;

public sealed class FakeClock(DateTimeOffset? utcNow = null) : IClock
{
    private DateTimeOffset _utcNow = utcNow ?? new DateTimeOffset(
        2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    public DateTimeOffset UtcNow => _utcNow;

    public DateTime UtcDateTime => _utcNow.UtcDateTime;

    public void Set(DateTimeOffset utcNow)
    {
        _utcNow = utcNow.ToUniversalTime();
    }

    public void Set(DateTime utcNow)
    {
        _utcNow = new DateTimeOffset(
            DateTime.SpecifyKind(utcNow, DateTimeKind.Utc));
    }

    public void Advance(TimeSpan delta)
    {
        _utcNow = _utcNow.Add(delta);
    }
}
