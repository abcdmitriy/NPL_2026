
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.charset.StandardCharsets

class BmpToPpm {

    static int readU8(byte[] data, int offset) {
        return data[offset] & 0xFF
    }

    static int readU16(byte[] data, int offset) {
        return readU8(data, offset) |
               (readU8(data, offset + 1) << 8)
    }

    static long readU32(byte[] data, int offset) {
        return ((long) readU8(data, offset)) |
               ((long) readU8(data, offset + 1) << 8) |
               ((long) readU8(data, offset + 2) << 16) |
               ((long) readU8(data, offset + 3) << 24)
    }

    static int readI32(byte[] data, int offset) {
        return (int) readU32(data, offset)
    }

    static void convert(String inputPath, String outputPath) {

        byte[] bmp = Files.readAllBytes(Paths.get(inputPath))

        if (bmp.length < 54) {
            throw new IOException("BMP file is too small")
        }

        // Проверка сигнатуры BMP
        if (readU8(bmp, 0) != 0x42 ||
            readU8(bmp, 1) != 0x4D) {
            throw new IOException("Invalid BMP signature")
        }

        // Чтение заголовка BMP
        long pixelOffset = readU32(bmp, 10)
        long dibSize = readU32(bmp, 14)

        if (dibSize < 40 || 14L + dibSize > bmp.length) {
            throw new IOException("Unsupported BMP header")
        }

        int width = readI32(bmp, 18)
        int rawHeight = readI32(bmp, 22)
        int planes = readU16(bmp, 26)
        int bitsPerPixel = readU16(bmp, 28)
        long compression = readU32(bmp, 30)

        // Проверка размеров изображения
        if (width <= 0 || rawHeight == 0 ||
            rawHeight == Integer.MIN_VALUE) {
            throw new IOException("Invalid image dimensions")
        }

        if (planes != 1) {
            throw new IOException("Invalid number of color planes")
        }

        if (bitsPerPixel != 24) {
            throw new IOException("Only 24-bit BMP is supported")
        }

        if (compression != 0) {
            throw new IOException("Compressed BMP is not supported")
        }

        int height = (int) Math.abs((long) rawHeight)

        // Отрицательная высота означает порядок сверху вниз
        boolean topDown = rawHeight < 0

        // Размер одной строки без выравнивания
        long rowSizeLong = (long) width * 3L

        if (rowSizeLong > Integer.MAX_VALUE) {
            throw new IOException("Image is too large")
        }

        // Выравнивание строки до границы 4 байт
        // Используется целочисленное деление
        long rowStrideLong =
            Math.floorDiv(rowSizeLong + 3L, 4L) * 4L

        // Проверка смещения пикселей
        if (pixelOffset < 14L + dibSize ||
            pixelOffset > bmp.length ||
            pixelOffset > Integer.MAX_VALUE) {
            throw new IOException("Invalid BMP pixel offset")
        }

        // Проверка размера данных пикселей
        long availableBytes = bmp.length - pixelOffset

        if (rowStrideLong > availableBytes / height) {
            throw new IOException("Not enough BMP pixel data")
        }

        int rowSize = (int) rowSizeLong
        int rowStride = (int) rowStrideLong

        // Формирование заголовка PPM P6
        String ppmHeader = "P6\n${width} ${height}\n255\n"

        def output = Files.newOutputStream(Paths.get(outputPath))

        try {
            // Запись заголовка PPM
            output.write(
                ppmHeader.getBytes(StandardCharsets.US_ASCII)
            )

            byte[] row = new byte[rowSize]

            // Обработка изображения сверху вниз
            for (int y = 0; y < height; y++) {

                int sourceY = topDown ? y : height - 1 - y

                int rowStart = (int) (
                    pixelOffset + (long) sourceY * rowStride
                )

                // Преобразование каждого пикселя BGR -> RGB
                for (int x = 0; x < width; x++) {

                    int sourceIndex = rowStart + x * 3
                    int targetIndex = x * 3

                    row[targetIndex] = bmp[sourceIndex + 2]
                    row[targetIndex + 1] = bmp[sourceIndex + 1]
                    row[targetIndex + 2] = bmp[sourceIndex]
                }

                // Запись строки в PPM
                output.write(row)
            }

        } finally {
            output.close()
        }

        println "Conversion completed successfully"
        println "Image size: ${width}x${height}"
        println "Output format: PPM P6"
        println "Output file: ${outputPath}"
    }
}

// Проверка аргументов командной строки
if (args.length != 2) {
    System.err.println(
        "Usage: groovy main.groovy input.bmp output.ppm"
    )
    System.exit(1)
}

try {
    BmpToPpm.convert(args[0], args[1])
} catch (Exception e) {
    System.err.println("Error: ${e.message}")
    System.exit(1)
}
