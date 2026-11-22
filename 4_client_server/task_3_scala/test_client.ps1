$ErrorActionPreference = 'Stop'

$client = [System.Net.Sockets.TcpClient]::new()

try {
    $client.Connect('127.0.0.1', 5000)

    $stream = $client.GetStream()

    $reader = [System.IO.StreamReader]::new(
        $stream,
        [System.Text.Encoding]::UTF8
    )

    $writer = [System.IO.StreamWriter]::new(
        $stream,
        [System.Text.UTF8Encoding]::new($false)
    )

    $writer.AutoFlush = $true

    Write-Host 'Connected to leaderboard server.'
    Write-Host 'Commands: SUBMIT, TOP, RANK, RESET, QUIT'
    Write-Host ''

    while ($true) {
        $command = Read-Host 'Command'

        if ([string]::IsNullOrWhiteSpace($command)) {
            continue
        }

        $writer.WriteLine($command)

        $response = $reader.ReadLine()

        if ($null -eq $response) {
            Write-Host 'Connection closed by server.'
            break
        }

        Write-Host $response

        if ($command.Trim().Equals(
            'QUIT',
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            break
        }
    }
}
catch {
    Write-Host ('Client error: ' + $_.Exception.Message)
}
finally {
    $client.Close()
}