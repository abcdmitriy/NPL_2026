
$ErrorActionPreference = "Stop"

$ServerHost = "127.0.0.1"
$ServerPort = 6000

$script:Passed = 0
$script:Failed = 0

# Connect to the polynomial server.
function Connect-Server {
    param(
        [string]$HostName,
        [int]$Port
    )

    $tcp = [System.Net.Sockets.TcpClient]::new()
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout = 5000

    $tcp.Connect($HostName, $Port)

    $stream = $tcp.GetStream()
    $stream.ReadTimeout = 5000
    $stream.WriteTimeout = 5000

    $reader = [System.IO.StreamReader]::new($stream)
    $writer = [System.IO.StreamWriter]::new($stream)
    $writer.AutoFlush = $true

    $welcome = $reader.ReadLine()

    return [PSCustomObject]@{
        TcpClient = $tcp
        Reader    = $reader
        Writer    = $writer
        Welcome   = $welcome
    }
}

# Send a command and receive a response.
function Send-Command {
    param(
        [object]$Connection,
        [string]$Command
    )

    $Connection.Writer.WriteLine($Command)

    $response = $Connection.Reader.ReadLine()

    if ($null -eq $response) {
        throw "Server closed the connection unexpectedly."
    }

    return $response
}

# Compare actual and expected responses.
function Assert-Response {
    param(
        [string]$TestName,
        [string]$Actual,
        [string]$Expected
    )

    if ($Actual -ceq $Expected) {
        $script:Passed++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
    }
    else {
        $script:Failed++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        Write-Host "  Expected: $Expected"
        Write-Host "  Actual:   $Actual"
    }
}

# Display an operation and its server response.
function Show-Operation {
    param(
        [string]$Title,
        [string]$Command,
        [string]$Calculation,
        [string]$Actual,
        [string]$Expected
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "Command: $Command"
    Write-Host ""
    Write-Host "Calculation:"
    Write-Host $Calculation -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Server response:"
    Write-Host $Actual -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Expected response:"
    Write-Host $Expected -ForegroundColor Green
}

# Close a client connection.
function Close-Connection {
    param([object]$Connection)

    if ($null -ne $Connection) {
        try {
            $Connection.TcpClient.Close()
        }
        catch {
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       D POLYNOMIAL TCP SERVER TESTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Server: ${ServerHost}:${ServerPort}"
Write-Host ""

$mainConnection = $null
$client1 = $null
$client2 = $null

try {

    # 1. Connection.

    Write-Host "[STEP] Connecting to server..."

    $mainConnection = Connect-Server $ServerHost $ServerPort

    Assert-Response `
        "Server greeting" `
        $mainConnection.Welcome `
        "OK Polynomial server ready. Coefficients: c0 c1 ... cn"


    # 2. Define polynomial a.

    Write-Host ""
    Write-Host "[STEP] Defining polynomial a..."

    $actual = Send-Command $mainConnection "DEF a 1 -2 3"

    Show-Operation `
        "POLYNOMIAL DEFINITION" `
        "DEF a 1 -2 3" `
        "a(x) = 1 - 2x + 3x^2" `
        $actual `
        "OK a = 3x^2 - 2x + 1"

    Assert-Response "DEF a" $actual "OK a = 3x^2 - 2x + 1"


    # 3. Define polynomial b.

    Write-Host ""
    Write-Host "[STEP] Defining polynomial b..."

    $actual = Send-Command $mainConnection "DEF b 0 1"

    Show-Operation `
        "POLYNOMIAL DEFINITION" `
        "DEF b 0 1" `
        "b(x) = x" `
        $actual `
        "OK b = x"

    Assert-Response "DEF b" $actual "OK b = x"


    # 4. Addition.

    $actual = Send-Command $mainConnection "ADD a b"

    Show-Operation `
        "POLYNOMIAL ADDITION" `
        "ADD a b" `
        "(3x^2 - 2x + 1) + (x)`n= 3x^2 - 2x + x + 1`n= 3x^2 - x + 1" `
        $actual `
        "OK r1 = 3x^2 - x + 1"

    Assert-Response "ADD a b" $actual "OK r1 = 3x^2 - x + 1"


    # 5. Multiplication.

    $actual = Send-Command $mainConnection "MUL a b"

    Show-Operation `
        "POLYNOMIAL MULTIPLICATION" `
        "MUL a b" `
        "(3x^2 - 2x + 1) * (x)`n= 3x^3 - 2x^2 + x" `
        $actual `
        "OK r2 = 3x^3 - 2x^2 + x"

    Assert-Response "MUL a b" $actual "OK r2 = 3x^3 - 2x^2 + x"


    # 6. Derivative.

    $actual = Send-Command $mainConnection "DIFF a"

    Show-Operation `
        "POLYNOMIAL DERIVATIVE" `
        "DIFF a" `
        "a(x) = 3x^2 - 2x + 1`na'(x) = 6x - 2" `
        $actual `
        "OK r3 = 6x - 2"

    Assert-Response "DIFF a" $actual "OK r3 = 6x - 2"


    # 7. Evaluation.

    $actual = Send-Command $mainConnection "EVAL a 2"

    Show-Operation `
        "POLYNOMIAL EVALUATION" `
        "EVAL a 2" `
        "a(2) = 3 * 2^2 - 2 * 2 + 1`n= 3 * 4 - 4 + 1`n= 12 - 4 + 1`n= 9" `
        $actual `
        "OK 9"

    Assert-Response "EVAL a 2" $actual "OK 9"


    # 8. Show polynomial.

    $actual = Send-Command $mainConnection "SHOW r1"

    Show-Operation `
        "SHOW POLYNOMIAL" `
        "SHOW r1" `
        "Saved polynomial:`nr1(x) = 3x^2 - x + 1" `
        $actual `
        "OK r1 = 3x^2 - x + 1"

    Assert-Response "SHOW r1" $actual "OK r1 = 3x^2 - x + 1"


    # 9. Error handling.

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "             ERROR HANDLING" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $actual = Send-Command $mainConnection "DEF bad 1 abc"
    Assert-Response "Invalid coefficient" $actual "ERROR invalid coefficient: abc"

    $actual = Send-Command $mainConnection "DEF empty"
    Assert-Response "Empty polynomial" $actual "ERROR empty polynomial"

    $actual = Send-Command $mainConnection "SHOW missing"
    Assert-Response "Unknown polynomial in SHOW" $actual "ERROR unknown polynomial: missing"

    $actual = Send-Command $mainConnection "ADD missing other"
    Assert-Response "Unknown polynomial in ADD" $actual "ERROR unknown polynomial: missing"


    # 10. Finish main connection.

    $actual = Send-Command $mainConnection "QUIT"
    Assert-Response "QUIT main connection" $actual "BYE"

    Close-Connection $mainConnection
    $mainConnection = $null


    # 11. Client isolation.

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "             CLIENT ISOLATION" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $client1 = Connect-Server $ServerHost $ServerPort
    $client2 = Connect-Server $ServerHost $ServerPort

    Assert-Response "Client 1 greeting" $client1.Welcome "OK Polynomial server ready. Coefficients: c0 c1 ... cn"

    Assert-Response "Client 2 greeting" $client2.Welcome "OK Polynomial server ready. Coefficients: c0 c1 ... cn"

    $actual = Send-Command $client1 "DEF p 1 2"
    Assert-Response "Define p in client 1" $actual "OK p = 2x + 1"

    $actual = Send-Command $client2 "SHOW p"
    Assert-Response "Client 2 cannot see client 1 polynomial" $actual "ERROR unknown polynomial: p"

    $actual = Send-Command $client2 "DEF p 5 6"
    Assert-Response "Define p in client 2" $actual "OK p = 6x + 5"

    $actual = Send-Command $client1 "SHOW p"
    Assert-Response "Client 1 keeps its own polynomial" $actual "OK p = 2x + 1"

    $actual = Send-Command $client1 "QUIT"
    Assert-Response "Client 1 QUIT" $actual "BYE"

    $actual = Send-Command $client2 "QUIT"
    Assert-Response "Client 2 QUIT" $actual "BYE"

}
catch {
    $script:Failed++

    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Close-Connection $mainConnection
    Close-Connection $client1
    Close-Connection $client2
}


# 12. Final summary.

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "                TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Passed: $script:Passed" -ForegroundColor Green
Write-Host "Failed: $script:Failed" -ForegroundColor Red

if ($script:Failed -eq 0) {
    Write-Host ""
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "SOME TESTS FAILED!" -ForegroundColor Red
}
