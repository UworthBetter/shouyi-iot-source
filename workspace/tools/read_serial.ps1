param(
    [string]$Port = 'COM6',
    [int]$Baud = 115200,
    [int]$Seconds = 10
)
$sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, 'None', 8, 'One')
$sp.ReadTimeout = 200
$sp.DtrEnable = $true
$sp.RtsEnable = $false
try { $sp.Open() } catch { Write-Host "OPEN_FAIL: $_"; exit 1 }
Write-Host "OPEN_OK $Port @$Baud"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$buf = New-Object System.Text.StringBuilder
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    try {
        $chunk = $sp.ReadExisting()
        if ($chunk.Length -gt 0) { [void]$buf.Append($chunk) }
    } catch {}
    Start-Sleep -Milliseconds 100
}
$sp.Close()
$out = $buf.ToString()
$bytes = [System.Text.Encoding]::UTF8.GetByteCount($out)
Write-Host "CAPTURED ${bytes} bytes in ${Seconds}s"
if ($out.Length -eq 0) {
    Write-Host 'NO_OUTPUT'
} else {
    Write-Host '--- OUTPUT (first 3000 chars) ---'
    if ($out.Length -gt 3000) { Write-Host $out.Substring(0,3000) } else { Write-Host $out }
}
