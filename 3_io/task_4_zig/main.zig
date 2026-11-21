const std = @import("std");

const BLOCK_SIZE = 64 * 1024;

// Самостоятельная реализация CRC32 (IEEE).
const CRC32 = struct {
    state: u32 = 0xFFFFFFFF,

    fn update(self: *CRC32, data: []const u8) void {
        for (data) |byte| {
            self.state ^= @as(u32, byte);

            for (0..8) |_| {
                if ((self.state & 1) != 0) {
                    self.state = (self.state >> 1) ^ 0xEDB88320;
                } else {
                    self.state >>= 1;
                }
            }
        }
    }

    fn finish(self: CRC32) u32 {
        return self.state ^ 0xFFFFFFFF;
    }
};

const FileHash = struct {
    crc32: u32,
    size: u64,
};

const Manifest = struct {
    source_crc32: u32,
    backup_crc32: u32,
    size: u64,
};

// Копирование файла блоками с вычислением CRC32.
fn copyFile(
    io: std.Io,
    source_path: []const u8,
    backup_path: []const u8,
) !FileHash {
    const source = try std.Io.Dir.cwd().openFile(io, source_path, .{});
    defer source.close(io);

    const backup = try std.Io.Dir.cwd().createFile(
        io,
        backup_path,
        .{ .truncate = true },
    );
    defer backup.close(io);

    var reader_buffer: [4096]u8 = undefined;
    var writer_buffer: [4096]u8 = undefined;
    var buffer: [BLOCK_SIZE]u8 = undefined;

    var reader = source.readerStreaming(io, &reader_buffer);
    var writer = backup.writerStreaming(io, &writer_buffer);

    var crc = CRC32{};
    var total_size: u64 = 0;

    while (true) {
        const bytes_read = try reader.interface.readSliceShort(&buffer);

        if (bytes_read == 0) break;

        const block = buffer[0..bytes_read];

        try writer.interface.writeAll(block);

        crc.update(block);
        total_size += @intCast(bytes_read);
    }

    try writer.flush();

    return .{
        .crc32 = crc.finish(),
        .size = total_size,
    };
}

// Независимое вычисление CRC32 файла.
fn calculateFileHash(
    io: std.Io,
    file_path: []const u8,
) !FileHash {
    const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);

    var reader_buffer: [4096]u8 = undefined;
    var buffer: [BLOCK_SIZE]u8 = undefined;

    var reader = file.readerStreaming(io, &reader_buffer);

    var crc = CRC32{};
    var total_size: u64 = 0;

    while (true) {
        const bytes_read = try reader.interface.readSliceShort(&buffer);

        if (bytes_read == 0) break;

        crc.update(buffer[0..bytes_read]);
        total_size += @intCast(bytes_read);
    }

    return .{
        .crc32 = crc.finish(),
        .size = total_size,
    };
}

// Запись контрольных сумм в манифест.
fn writeManifest(
    io: std.Io,
    manifest_path: []const u8,
    source_hash: FileHash,
    backup_hash: FileHash,
) !void {
    const file = try std.Io.Dir.cwd().createFile(
        io,
        manifest_path,
        .{ .truncate = true },
    );
    defer file.close(io);

    var content_buffer: [512]u8 = undefined;

    const content = try std.fmt.bufPrint(
        &content_buffer,
        "CRC32-MANIFEST-V1\nsource_crc32={d}\nbackup_crc32={d}\nsize={d}\n",
        .{
            source_hash.crc32,
            backup_hash.crc32,
            source_hash.size,
        },
    );

    var writer_buffer: [512]u8 = undefined;
    var writer = file.writerStreaming(io, &writer_buffer);

    try writer.interface.writeAll(content);
    try writer.flush();
}

// Чтение числового поля из манифеста.
fn parseManifestField(
    comptime T: type,
    line: []const u8,
    expected_key: []const u8,
) !T {
    const separator = std.mem.indexOfScalar(u8, line, '=') orelse {
        return error.InvalidManifest;
    };

    if (!std.mem.eql(u8, line[0..separator], expected_key)) {
        return error.InvalidManifest;
    }

    return std.fmt.parseInt(
        T,
        line[separator + 1 ..],
        10,
    ) catch {
        return error.InvalidManifest;
    };
}

// Чтение манифеста.
fn readManifest(
    io: std.Io,
    manifest_path: []const u8,
) !Manifest {
    const file = try std.Io.Dir.cwd().openFile(io, manifest_path, .{});
    defer file.close(io);

    var reader_buffer: [512]u8 = undefined;
    var content_buffer: [4096]u8 = undefined;

    var reader = file.readerStreaming(io, &reader_buffer);

    const content_size = try reader.interface.readSliceShort(&content_buffer);

    if (content_size == content_buffer.len) {
        return error.ManifestTooLarge;
    }

    const content = content_buffer[0..content_size];

    var lines = std.mem.splitScalar(u8, content, '\n');

    const header = lines.next() orelse return error.InvalidManifest;
    const source_line = lines.next() orelse return error.InvalidManifest;
    const backup_line = lines.next() orelse return error.InvalidManifest;
    const size_line = lines.next() orelse return error.InvalidManifest;

    if (!std.mem.eql(
        u8,
        std.mem.trim(u8, header, "\r"),
        "CRC32-MANIFEST-V1",
    )) {
        return error.InvalidManifest;
    }

    return .{
        .source_crc32 = try parseManifestField(
            u32,
            std.mem.trim(u8, source_line, "\r"),
            "source_crc32",
        ),

        .backup_crc32 = try parseManifestField(
            u32,
            std.mem.trim(u8, backup_line, "\r"),
            "backup_crc32",
        ),

        .size = try parseManifestField(
            u64,
            std.mem.trim(u8, size_line, "\r"),
            "size",
        ),
    };
}

// Создание резервной копии и манифеста.
fn createBackup(
    allocator: std.mem.Allocator,
    io: std.Io,
    source_path: []const u8,
    destination_dir: []const u8,
) !void {
    const file_name = std.fs.path.basename(source_path);

    const backup_name = try std.fmt.allocPrint(
        allocator,
        "{s}.bak",
        .{file_name},
    );

    const manifest_name = try std.fmt.allocPrint(
        allocator,
        "{s}.manifest",
        .{file_name},
    );

    const backup_path = try std.fs.path.join(
        allocator,
        &.{ destination_dir, backup_name },
    );

    const manifest_path = try std.fs.path.join(
        allocator,
        &.{ destination_dir, manifest_name },
    );

    // Копирование и вычисление CRC32 исходного файла.
    const source_hash = try copyFile(
        io,
        source_path,
        backup_path,
    );

    // Повторное чтение копии и вычисление ее CRC32.
    const backup_hash = try calculateFileHash(
        io,
        backup_path,
    );

    if (source_hash.crc32 != backup_hash.crc32 or
        source_hash.size != backup_hash.size)
    {
        std.debug.print(
            "Ошибка: резервная копия не прошла проверку!\n",
            .{},
        );

        return error.CopyVerificationFailed;
    }

    try writeManifest(
        io,
        manifest_path,
        source_hash,
        backup_hash,
    );

    std.debug.print("Резервная копия создана: {s}\n", .{backup_path});
    std.debug.print("Манифест создан: {s}\n", .{manifest_path});

    std.debug.print(
        "CRC32 исходного файла: 0x{x}\n",
        .{source_hash.crc32},
    );

    std.debug.print(
        "CRC32 резервной копии: 0x{x}\n",
        .{backup_hash.crc32},
    );

    std.debug.print(
        "Размер файла: {d} байт\n",
        .{source_hash.size},
    );
}

// Проверка резервной копии.
fn verifyBackup(
    io: std.Io,
    backup_path: []const u8,
    manifest_path: []const u8,
) !void {
    const manifest = try readManifest(io, manifest_path);

    const actual_hash = try calculateFileHash(
        io,
        backup_path,
    );

    const checksum_matches =
        actual_hash.crc32 == manifest.source_crc32 and
        actual_hash.crc32 == manifest.backup_crc32;

    const size_matches = actual_hash.size == manifest.size;

    if (!checksum_matches or !size_matches) {
        std.debug.print(
            "ОШИБКА: резервная копия повреждена или изменена!\n",
            .{},
        );

        std.debug.print(
            "Ожидаемый CRC32: 0x{x}\n",
            .{manifest.source_crc32},
        );

        std.debug.print(
            "CRC32 копии из манифеста: 0x{x}\n",
            .{manifest.backup_crc32},
        );

        std.debug.print(
            "Полученный CRC32: 0x{x}\n",
            .{actual_hash.crc32},
        );

        std.debug.print(
            "Ожидаемый размер: {d} байт\n",
            .{manifest.size},
        );

        std.debug.print(
            "Фактический размер: {d} байт\n",
            .{actual_hash.size},
        );

        return error.BackupCorrupted;
    }

    std.debug.print(
        "Проверка пройдена: резервная копия не повреждена.\n",
        .{},
    );

    std.debug.print(
        "CRC32: 0x{x}\n",
        .{actual_hash.crc32},
    );

    std.debug.print(
        "Размер: {d} байт\n",
        .{actual_hash.size},
    );
}

fn printUsage() void {
    std.debug.print(
        "Использование:\n" ++
            "  zig run main.zig -- backup <исходный_файл> <каталог>\n" ++
            "  zig run main.zig -- verify <файл_копии> <файл_манифеста>\n",
        .{},
    );
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();

    // Пропускаем имя исполняемой программы.
    _ = args.next();

    const command = args.next() orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, command, "backup")) {
        const source_path = args.next() orelse {
            printUsage();
            return;
        };

        const destination_dir = args.next() orelse {
            printUsage();
            return;
        };

        if (args.next() != null) {
            printUsage();
            return;
        }

        try createBackup(
            allocator,
            io,
            source_path,
            destination_dir,
        );
    } else if (std.mem.eql(u8, command, "verify")) {
        const backup_path = args.next() orelse {
            printUsage();
            return;
        };

        const manifest_path = args.next() orelse {
            printUsage();
            return;
        };

        if (args.next() != null) {
            printUsage();
            return;
        }

        try verifyBackup(
            io,
            backup_path,
            manifest_path,
        );
    } else {
        printUsage();
    }
}

test "CRC32 standard test vector" {
    var crc = CRC32{};
    crc.update("123456789");

    try std.testing.expectEqual(
        @as(u32, 0xCBF43926),
        crc.finish(),
    );
}
