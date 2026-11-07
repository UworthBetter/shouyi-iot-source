param(
    [Parameter(Mandatory=$true)][string[]]$Ports,
    [int]$Seconds = 120
)
$ErrorActionPreference = 'Stop'
$opened = @()
$capture = @{}
$writers = @{}
$readErrors = @{}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    foreach ($portName in $Ports) {
        $serial = New-Object System.IO.Ports.SerialPort($portName, 115200, 'None', 8, 'One')
        $serial.DtrEnable = $true
        $serial.RtsEnable = $false
        $serial.Open()
        $opened += $serial
        $capture[$portName] = New-Object System.Text.StringBuilder
        $readErrors[$portName] = 0
        $livePath = Join-Path $PSScriptRoot "..\logs\${stamp}_${portName}_stability.log"
        $writers[$portName] = [IO.StreamWriter]::new($livePath, $false, [Text.UTF8Encoding]::new($false))
        $writers[$portName].AutoFlush = $true
    }
    Write-Output "Capturing $($Ports -join ', ') for $Seconds seconds"
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        foreach ($serial in $opened) {
            if (-not $serial.IsOpen) { continue }
            try {
                $chunk = $serial.ReadExisting()
                [void]$capture[$serial.PortName].Append($chunk)
                $writers[$serial.PortName].Write($chunk)
            } catch {
                $readErrors[$serial.PortName]++
                $serial.Close()
            }
        }
        Start-Sleep -Milliseconds 100
    }
} finally {
    foreach ($serial in $opened) {
        if ($serial.IsOpen) {
            try { [void]$capture[$serial.PortName].Append($serial.ReadExisting()) }
            catch { $readErrors[$serial.PortName]++ }
            $serial.Close()
        }
        $serial.Dispose()
    }
    foreach ($writer in $writers.Values) { $writer.Dispose() }
    foreach ($portName in $capture.Keys) {
        $raw = $capture[$portName].ToString()
        $logPath = Join-Path $PSScriptRoot "..\logs\${stamp}_${portName}_stability.log"
        [IO.File]::WriteAllText($logPath, $raw)
        [ordered]@{
            port = $portName
            log = [IO.Path]::GetFullPath($logPath)
            bytes = [Text.Encoding]::UTF8.GetByteCount($raw)
            read_errors = $readErrors[$portName]
            reports = [regex]::Matches($raw, 'report #\d+ sent').Count
            received = [regex]::Matches($raw, 'recv \d+ bytes from server').Count
            publish_ok = [regex]::Matches($raw, 'publish completion rc=0').Count
            publish_fail = [regex]::Matches($raw, 'publish fail').Count
            relay_forward_ok = [regex]::Matches($raw, '\[sy relay\] received=\d+ forwarded=\d+ dropped=\d+ rc=0x0 data=').Count
            received_via_relay = [regex]::Matches($raw, 'recv [^\r\n]*"via":"sy-r-001"').Count
            stack_overflow = [regex]::Matches($raw, 'stack overflow').Count
            exceptions = [regex]::Matches($raw, 'APP\|exception:').Count
        } | ConvertTo-Json -Compress | Write-Output
        ($raw -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 8) | Write-Output
    }
}
