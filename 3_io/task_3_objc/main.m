
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>

int main(int argc, const char * argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    // 1. Проверка аргументов
    if (argc != 3) {
        fprintf(stderr, "Использование: %s <файл> <N>\n", argv[0]);
        [pool drain];
        return 1;
    }

    NSString *filePath = [NSString stringWithUTF8String:argv[1]];

    if (filePath == nil) {
        fprintf(stderr, "Ошибка: некорректное имя файла\n");
        [pool drain];
        return 1;
    }

    const char *number = argv[2];

    while (*number == ' ' || *number == '\t' ||
           *number == '\n' || *number == '\r') {
        number++;
    }

    char *endPtr = NULL;
    errno = 0;

    unsigned long long n = strtoull(argv[2], &endPtr, 10);

    if (errno == ERANGE || endPtr == argv[2] ||
        *endPtr != '\0' || *number == '-' || n == 0) {
        fprintf(stderr, "Ошибка: N должно быть положительным целым числом\n");
        [pool drain];
        return 1;
    }

    // 2. Открытие файла
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:filePath];

    if (file == nil) {
        fprintf(stderr, "Ошибка: не удалось открыть файл\n");
        [pool drain];
        return 1;
    }

    unsigned long long fileSize = [file seekToEndOfFile];
    const NSUInteger chunkSize = 4096;

    if (fileSize == 0) {
        printf("Байтовое смещение начала первой выведенной строки: 0\n");
        [file closeFile];
        [pool drain];
        return 0;
    }

    // 3. Поиск начала последних N строк с конца файла
    unsigned long long position = fileSize;
    unsigned long long remainingLines = n;
    unsigned long long targetOffset = 0;

    BOOL firstByteFromEnd = YES;
    BOOL found = NO;

    while (position > 0 && remainingLines > 0) {
        NSAutoreleasePool *chunkPool = [[NSAutoreleasePool alloc] init];

        NSUInteger readSize = (position >= chunkSize)
            ? chunkSize
            : (NSUInteger)position;

        unsigned long long chunkStart = position - readSize;

        [file seekToFileOffset:chunkStart];

        NSData *chunk = [file readDataOfLength:readSize];

        if ([chunk length] != readSize) {
            fprintf(stderr, "Ошибка: не удалось прочитать блок файла\n");
            [chunkPool drain];
            [file closeFile];
            [pool drain];
            return 1;
        }

        const unsigned char *bytes = [chunk bytes];
        NSUInteger i = [chunk length];

        while (i > 0) {
            --i;

            // Пропускаем один завершающий LF, если он есть
            if (firstByteFromEnd) {
                firstByteFromEnd = NO;

                if (bytes[i] == '\n') {
                    continue;
                }
            }

            if (bytes[i] == '\n') {
                remainingLines--;

                if (remainingLines == 0) {
                    targetOffset = chunkStart + i + 1;
                    found = YES;
                    break;
                }
            }
        }

        position = chunkStart;
        [chunkPool drain];

        if (found) {
            break;
        }
    }

    // Если строк меньше N, выводим весь файл
    if (!found) {
        targetOffset = 0;
    }

    // 4. Вывод байтового смещения
    printf("Байтовое смещение начала первой выведенной строки: %llu\n",
           targetOffset);

    fflush(stdout);

    // 5. Вывод найденного фрагмента блоками
    [file seekToFileOffset:targetOffset];

    while (YES) {
        NSAutoreleasePool *outputPool = [[NSAutoreleasePool alloc] init];

        NSData *data = [file readDataOfLength:chunkSize];
        NSUInteger length = [data length];

        if (length == 0) {
            [outputPool drain];
            break;
        }

        size_t written = fwrite([data bytes], 1, length, stdout);

        [outputPool drain];

        if (written != length) {
            fprintf(stderr, "Ошибка: не удалось вывести данные\n");
            [file closeFile];
            [pool drain];
            return 1;
        }
    }

    [file closeFile];
    [pool drain];

    return 0;
}
