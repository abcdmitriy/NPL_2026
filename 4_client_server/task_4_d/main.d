
import core.thread : Thread;
import std.array : split;
import std.conv : to;
import std.socket : TcpSocket, Socket, InternetAddress;
import std.stdio : writeln;
import std.string : strip;
import std.uni : toUpper;

alias Polynomial = long[];

enum ushort DEFAULT_PORT = 6000;
enum size_t MAX_COMMAND_LENGTH = 65536;

// Проверка преобразования строки в целое число.
bool tryParseLong(string text, out long value)
{
    try
    {
        value = to!long(text);
        return true;
    }
    catch (Exception)
    {
        value = 0;
        return false;
    }
}

// Проверка переполнения при сложении.
long checkedAdd(long a, long b)
{
    if ((b > 0 && a > long.max - b) ||
        (b < 0 && a < long.min - b))
    {
        throw new Exception("integer overflow");
    }

    return a + b;
}

// Проверка переполнения при умножении.
long checkedMultiply(long a, long b)
{
    if (a == 0 || b == 0)
        return 0;

    if (a > 0)
    {
        if (b > 0)
        {
            if (a > long.max / b)
                throw new Exception("integer overflow");
        }
        else
        {
            if (b < long.min / a)
                throw new Exception("integer overflow");
        }
    }
    else
    {
        if (b > 0)
        {
            if (a < long.min / b)
                throw new Exception("integer overflow");
        }
        else
        {
            if (a < long.max / b)
                throw new Exception("integer overflow");
        }
    }

    return a * b;
}

// Удаление нулевых коэффициентов старших степеней.
Polynomial normalize(Polynomial polynomial)
{
    if (polynomial.length == 0)
        return [0L];

    while (polynomial.length > 1 &&
           polynomial[$ - 1] == 0)
    {
        polynomial = polynomial[0 .. $ - 1];
    }

    return polynomial;
}

// Представление полинома в виде строки.
string formatPolynomial(Polynomial polynomial)
{
    auto p = normalize(polynomial);

    string result;

    for (size_t i = p.length; i > 0; --i)
    {
        size_t power = i - 1;
        long coefficient = p[power];

        if (coefficient == 0)
            continue;

        bool negative = coefficient < 0;

        ulong magnitude;

        if (negative)
        {
            magnitude = cast(ulong)(-(coefficient + 1L)) + 1UL;
        }
        else
        {
            magnitude = cast(ulong)coefficient;
        }

        if (result.length > 0)
        {
            if (negative)
                result ~= " - ";
            else
                result ~= " + ";
        }
        else if (negative)
        {
            result ~= "-";
        }

        if (power == 0 || magnitude != 1)
            result ~= to!string(magnitude);

        if (power > 0)
        {
            result ~= "x";

            if (power > 1)
                result ~= "^" ~ to!string(power);
        }
    }

    if (result.length == 0)
        return "0";

    return result;
}

// Сложение двух полиномов.
Polynomial addPolynomials(
    Polynomial a,
    Polynomial b)
{
    size_t count = a.length > b.length
        ? a.length
        : b.length;

    auto result = new long[count];

    foreach (i; 0 .. count)
    {
        long left = i < a.length ? a[i] : 0;
        long right = i < b.length ? b[i] : 0;

        result[i] = checkedAdd(left, right);
    }

    return normalize(result);
}

// Умножение двух полиномов.
Polynomial multiplyPolynomials(
    Polynomial a,
    Polynomial b)
{
    auto result = new long[a.length + b.length - 1];

    for (size_t i = 0; i < a.length; ++i)
    {
        for (size_t j = 0; j < b.length; ++j)
        {
            long product = checkedMultiply(a[i], b[j]);

            result[i + j] = checkedAdd(
                result[i + j],
                product
            );
        }
    }

    return normalize(result);
}

// Производная полинома.
Polynomial derivativePolynomial(Polynomial p)
{
    if (p.length <= 1)
        return [0L];

    auto result = new long[p.length - 1];

    for (size_t i = 1; i < p.length; ++i)
    {
        result[i - 1] = checkedMultiply(
            p[i],
            cast(long)i
        );
    }

    return normalize(result);
}

// Вычисление значения полинома в точке x.
long evaluatePolynomial(Polynomial p, long x)
{
    long result = 0;

    for (size_t i = p.length; i > 0; --i)
    {
        result = checkedMultiply(result, x);
        result = checkedAdd(result, p[i - 1]);
    }

    return result;
}

// Получение полинома по имени.
bool getPolynomial(
    Polynomial[string] table,
    string name,
    out Polynomial polynomial,
    out string errorMessage)
{
    if (name !in table)
    {
        errorMessage = "unknown polynomial: " ~ name;
        polynomial = null;
        return false;
    }

    polynomial = table[name];

    if (polynomial.length == 0)
    {
        errorMessage = "empty polynomial: " ~ name;
        return false;
    }

    errorMessage = "";
    return true;
}

// Сохранение результата под новым именем.
string storeResult(
    Polynomial polynomial,
    ref Polynomial[string] table,
    ref size_t nextResultId)
{
    string resultName;

    do
    {
        resultName = "r" ~ to!string(nextResultId);
        ++nextResultId;
    }
    while (resultName in table);

    table[resultName] = normalize(polynomial).dup;

    return "OK " ~ resultName ~ " = " ~
        formatPolynomial(polynomial);
}

// Обработка одной команды клиента.
string processCommand(
    string line,
    ref Polynomial[string] table,
    ref size_t nextResultId,
    out bool shouldQuit)
{
    shouldQuit = false;

    auto tokens = split(strip(line));

    if (tokens.length == 0)
        return "";

    string command = toUpper(tokens[0]);

    try
    {
        switch (command)
        {
            // DEF имя коэффициенты
            case "DEF":
            {
                if (tokens.length < 2)
                    return "ERROR missing polynomial name";

                if (tokens.length == 2)
                    return "ERROR empty polynomial";

                string name = tokens[1];

                if (name in table)
                    return "ERROR polynomial already exists: " ~ name;

                Polynomial coefficients;

                foreach (coefficientText; tokens[2 .. $])
                {
                    long coefficient;

                    if (!tryParseLong(coefficientText, coefficient))
                    {
                        return "ERROR invalid coefficient: " ~
                            coefficientText;
                    }

                    coefficients ~= coefficient;
                }

                if (coefficients.length == 0)
                    return "ERROR empty polynomial";

                coefficients = normalize(coefficients);

                table[name] = coefficients;

                return "OK " ~ name ~ " = " ~
                    formatPolynomial(coefficients);
            }

            // ADD a b
            case "ADD":
            {
                if (tokens.length != 3)
                    return "ERROR usage: ADD a b";

                Polynomial a;
                Polynomial b;
                string errorMessage;

                if (!getPolynomial(table, tokens[1], a, errorMessage))
                    return "ERROR " ~ errorMessage;

                if (!getPolynomial(table, tokens[2], b, errorMessage))
                    return "ERROR " ~ errorMessage;

                auto result = addPolynomials(a, b);

                return storeResult(
                    result,
                    table,
                    nextResultId
                );
            }

            // MUL a b
            case "MUL":
            {
                if (tokens.length != 3)
                    return "ERROR usage: MUL a b";

                Polynomial a;
                Polynomial b;
                string errorMessage;

                if (!getPolynomial(table, tokens[1], a, errorMessage))
                    return "ERROR " ~ errorMessage;

                if (!getPolynomial(table, tokens[2], b, errorMessage))
                    return "ERROR " ~ errorMessage;

                auto result = multiplyPolynomials(a, b);

                return storeResult(
                    result,
                    table,
                    nextResultId
                );
            }

            // DIFF a
            case "DIFF":
            {
                if (tokens.length != 2)
                    return "ERROR usage: DIFF a";

                Polynomial a;
                string errorMessage;

                if (!getPolynomial(table, tokens[1], a, errorMessage))
                    return "ERROR " ~ errorMessage;

                auto result = derivativePolynomial(a);

                return storeResult(
                    result,
                    table,
                    nextResultId
                );
            }

            // EVAL a x
            case "EVAL":
            {
                if (tokens.length != 3)
                    return "ERROR usage: EVAL a x";

                Polynomial a;
                string errorMessage;

                if (!getPolynomial(table, tokens[1], a, errorMessage))
                    return "ERROR " ~ errorMessage;

                long x;

                if (!tryParseLong(tokens[2], x))
                    return "ERROR invalid integer x";

                long value = evaluatePolynomial(a, x);

                return "OK " ~ to!string(value);
            }

            // SHOW a
            case "SHOW":
            {
                if (tokens.length != 2)
                    return "ERROR usage: SHOW a";

                Polynomial a;
                string errorMessage;

                if (!getPolynomial(table, tokens[1], a, errorMessage))
                    return "ERROR " ~ errorMessage;

                return "OK " ~ tokens[1] ~ " = " ~
                    formatPolynomial(a);
            }

            // QUIT
            case "QUIT":
            {
                if (tokens.length != 1)
                    return "ERROR usage: QUIT";

                shouldQuit = true;
                return "BYE";
            }

            default:
                return "ERROR unknown command. Commands: DEF ADD MUL DIFF EVAL SHOW QUIT";
        }
    }
    catch (Exception e)
    {
        return "ERROR " ~ e.msg;
    }
}

// Отправка строки клиенту.
bool sendLine(Socket client, string message)
{
    string payload = message ~ "\r\n";

    size_t sentTotal = 0;

    while (sentTotal < payload.length)
    {
        auto sent = client.send(
            cast(const(void)[])payload[sentTotal .. $]
        );

        if (sent <= 0)
            return false;

        sentTotal += cast(size_t)sent;
    }

    return true;
}

// Выполнение команды и отправка ответа.
bool executeLine(
    Socket client,
    string line,
    ref Polynomial[string] table,
    ref size_t nextResultId)
{
    bool shouldQuit = false;

    string response = processCommand(
        line,
        table,
        nextResultId,
        shouldQuit
    );

    if (response.length > 0)
    {
        if (!sendLine(client, response))
            return true;
    }

    return shouldQuit;
}

// Обработка отдельного подключения.
void handleClient(Socket client)
{
    scope(exit)
        client.close();

    // У каждого клиента собственная таблица.
    Polynomial[string] table;

    size_t nextResultId = 1;

    if (!sendLine(
        client,
        "OK Polynomial server ready. Coefficients: c0 c1 ... cn"
    ))
    {
        return;
    }

    ubyte[4096] buffer;

    string pending;

    bool shouldClose = false;

    while (!shouldClose)
    {
        long received;

        try
        {
            received = client.receive(buffer[]);
        }
        catch (Exception)
        {
            break;
        }

        if (received <= 0)
            break;

        pending ~= cast(string)buffer[0 .. cast(size_t)received];

        // Обрабатываем все полные строки.
        while (true)
        {
            size_t newlineIndex = 0;

            while (newlineIndex < pending.length &&
                   pending[newlineIndex] != '\n')
            {
                ++newlineIndex;
            }

            if (newlineIndex == pending.length)
                break;

            string line = pending[0 .. newlineIndex].idup;

            pending = pending[newlineIndex + 1 .. $].idup;

            // Поддержка CRLF.
            if (line.length > 0 &&
                line[$ - 1] == '\r')
            {
                line = line[0 .. $ - 1];
            }

            if (line.length > MAX_COMMAND_LENGTH)
            {
                if (!sendLine(client, "ERROR command too long"))
                {
                    shouldClose = true;
                    break;
                }

                continue;
            }

            if (executeLine(
                client,
                line,
                table,
                nextResultId
            ))
            {
                shouldClose = true;
                break;
            }
        }

        // Ограничиваем размер незавершённой команды.
        if (!shouldClose &&
            pending.length > MAX_COMMAND_LENGTH)
        {
            if (!sendLine(client, "ERROR command too long"))
            {
                shouldClose = true;
                break;
            }

            pending = "";
        }
    }

    // Обработка последней команды, если клиент закрыл
    // соединение без завершающего символа новой строки.
    if (!shouldClose && pending.length > 0)
    {
        string lastLine = strip(pending).idup;

        if (lastLine.length > 0)
        {
            if (lastLine.length > MAX_COMMAND_LENGTH)
            {
                sendLine(client, "ERROR command too long");
            }
            else
            {
                executeLine(
                    client,
                    lastLine,
                    table,
                    nextResultId
                );
            }
        }
    }

    writeln("Client disconnected.");
}

// Главная функция сервера.
void main(string[] args)
{
    ushort port = DEFAULT_PORT;

    if (args.length > 2)
    {
        writeln("Usage: server.exe [port]");
        return;
    }

    if (args.length == 2)
    {
        long parsedPort;

        if (!tryParseLong(args[1], parsedPort) ||
            parsedPort < 1 ||
            parsedPort > 65535)
        {
            writeln("ERROR invalid port");
            return;
        }

        port = cast(ushort)parsedPort;
    }

    auto server = new TcpSocket();

    scope(exit)
        server.close();

    try
    {
        // Принимаем подключения на всех сетевых интерфейсах.
        server.bind(new InternetAddress(port));
        server.listen(32);

        writeln("TCP polynomial server listening on port ", port);

        while (true)
        {
            auto client = server.accept();

            writeln("New client connected.");

            // Каждый клиент обслуживается отдельным потоком.
            new Thread({
                handleClient(client);
            }).start();
        }
    }
    catch (Exception e)
    {
        writeln("Server error: ", e.msg);
    }
}
