# Кодировка консоли
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

# Подключение к серверу
$client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 4000)
$stream = $client.GetStream()
$stream.ReadTimeout = 3000

# Кодировка TCP-потока
$utf8 = New-Object System.Text.UTF8Encoding($false)

$writer = New-Object System.IO.StreamWriter($stream, $utf8)
$writer.NewLine = "`n"

$reader = New-Object System.IO.StreamReader($stream, $utf8)

# Отправка команды и получение ответа
function Send-Cmd($cmd) {
    $writer.WriteLine($cmd)
    $writer.Flush()

    Write-Host ">> $cmd" -ForegroundColor Cyan

    try {
        $line = $reader.ReadLine()
        Write-Host "<< $line" -ForegroundColor Green
    }
    catch {
        Write-Host "<< TIMEOUT" -ForegroundColor Red
    }
}

Write-Host "=== Тестирование калькулятора ===" -ForegroundColor Yellow

Send-Cmd "SET x 10"
Send-Cmd "SET y 3"
Send-Cmd "EVAL x + y"
Send-Cmd "EVAL x * y - 2"
Send-Cmd "EVAL (x + y) * 2"
Send-Cmd "EVAL x / 0"
Send-Cmd "EVAL z + 1"
Send-Cmd "EVAL x +"
Send-Cmd "VARS"
Send-Cmd "QUIT"

# Закрытие соединения
$reader.Close()
$writer.Close()
$client.Close()

Write-Host "=== Тест завершен ===" -ForegroundColor Yellow