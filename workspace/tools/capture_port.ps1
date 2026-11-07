param(
    [Parameter(Mandatory=$true)][string]$Port,
    [int]$Seconds = 20,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new($Port,115200,'None',8,'One')
$serial.DtrEnable = $true
$serial.RtsEnable = $false
$serial.ReadTimeout = 200
$capture = [System.Text.StringBuilder]::new()
$encoding = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutputPath,'',$encoding)
try {
    $serial.Open()
    Write-Output "Listening on $Port for $Seconds seconds"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        $chunk = $serial.ReadExisting()
        if ($chunk.Length -gt 0) {
            [void]$capture.Append($chunk)
            [System.IO.File]::AppendAllText($OutputPath,$chunk,$encoding)
        }
        Start-Sleep -Milliseconds 100
    }
    [void]$capture.Append($serial.ReadExisting())
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    [System.IO.File]::WriteAllText($OutputPath,$capture.ToString(),$encoding)
}
Write-Output "Saved $($capture.Length) characters to $OutputPath"
