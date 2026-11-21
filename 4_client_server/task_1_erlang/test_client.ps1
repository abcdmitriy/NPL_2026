[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 4000)
$stream = $client.GetStream()
$stream.ReadTimeout = 3000

$writer = New-Object System.IO.StreamWriter($stream)
$writer.NewLine = "`n"
$reader = New-Object System.IO.StreamReader($stream)

function Send-Cmd($cmd) {
    $writer.WriteLine($cmd)
    $writer.Flush()
    try {
        $line = $reader.ReadLine()
        Write-Host ">> $cmd" -ForegroundColor Cyan
        Write-Host "<< $line" -ForegroundColor Green
    } catch {
        Write-Host ">> $cmd" -ForegroundColor Cyan
        Write-Host "<< TIMEOUT" -ForegroundColor Red
    }
}

Write-Host "=== Тестирование сервера таймеров ===" -ForegroundColor Yellow

Send-Cmd "START my_timer 5"
Send-Cmd "START my_timer 5"
Send-Cmd "START bad_timer abc"
Send-Cmd "LIST"
Send-Cmd "UNKNOWN_CMD"

Write-Host "`nЖдем 6 секунд..." -ForegroundColor Yellow
Start-Sleep -Seconds 6

try {
    $expired = $reader.ReadLine()
    Write-Host "<< $expired" -ForegroundColor Magenta
} catch {
    Write-Host "<< TIMEOUT" -ForegroundColor Red
}

Send-Cmd "STOP my_timer"
Send-Cmd "LIST"
Send-Cmd "QUIT"
$client.Close()
Write-Host "=== Тест завершен ===" -ForegroundColor Yellow