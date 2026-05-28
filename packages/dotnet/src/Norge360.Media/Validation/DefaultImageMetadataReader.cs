// <copyright file="DefaultImageMetadataReader.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Media.Abstractions;
using Norge360.Media.Models;

namespace Norge360.Media.Validation;

public sealed class DefaultImageMetadataReader : IImageMetadataReader
{
    public async Task<ImageMetadata> ReadAsync(Stream content, CancellationToken cancellationToken)
    {
        var header = new byte[64];
        var read = await content.ReadAsync(header.AsMemory(0, header.Length), cancellationToken);
        content.Position = 0;
        if (read < 24)
        {
            return new(null, null);
        }

        if (header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47)
        {
            var width = ReadBigEndianInt32(header, 16);
            var height = ReadBigEndianInt32(header, 20);
            return new(width, height);
        }

        if (header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 && header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50)
        {
            return new(null, null);
        }

        return new(null, null);
    }

    private static int ReadBigEndianInt32(byte[] source, int offset)
        => (source[offset] << 24) | (source[offset + 1] << 16) | (source[offset + 2] << 8) | source[offset + 3];
}
