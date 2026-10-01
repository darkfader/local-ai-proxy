$ErrorActionPreference = "Stop"

# Check if local server is running on 127.0.0.1:9931
$localServerRunning = (Get-NetTCPConnection -LocalPort 9931 -ErrorAction SilentlyContinue) -ne $null

if (-not $localServerRunning) {
    Write-Host "Starting local server..."
    # Start server with the josiefied model (abliteration + recovery fine-tune that
    # preserves real tool-calling, unlike huihui-ai's abliterated/abliterated-v2 or
    # the raw Heretic build -- verified directly, see start-server.ps1's -Model list).
    # Run in its own window: start-server.ps1 blocks in the foreground until Ctrl+C,
    # so it must not run inline here or this script (and everything after it) would hang.
    Start-Process -FilePath "pwsh" -ArgumentList @(
        "-NoExit", "-File", "D:\local-ai\start-server.ps1", "-Model", "josiefied", "-Port", "9931"
    )

    # Wait for server to be ready (simple health check)
    $timeout = 180
    $startTime = Get-Date
    while (-not (Get-NetTCPConnection -LocalPort 9931 -ErrorAction SilentlyContinue)) {
        if ((Get-Date) -gt ($startTime.AddSeconds($timeout))) {
            throw "Local server failed to start within $timeout seconds"
        }
        Start-Sleep -Seconds 1
    }
}

# Start proxy server
Write-Host "Starting proxy server..."
$proxyPort = 8090
$pythonExe = "python" # Or "python3" depending on system
$proxyScript = "D:\local-ai\proxy\lite_llm_proxy.py"

# Set proxy environment variables
$env:ANTHROPIC_BASE_URL = "http://127.0.0.1:$proxyPort"
$env:ANTHROPIC_API_KEY = $null
$env:ANTHROPIC_AUTH_TOKEN = $null

# Start proxy in new window. -WorkingDirectory pins it to the proxy's own directory
# regardless of the caller's CWD, since lite_llm_proxy.py/detect.py load rules.toml
# and write logs/fallback.jsonl via paths relative to the process's working directory.
Start-Process -FilePath $pythonExe -ArgumentList $proxyScript -NoNewWindow -WorkingDirectory "D:\local-ai\proxy"

# Wait for proxy to be ready (a real health check, not just "something answers the port" --
# a dead/stale proxy can still hold the port without ever completing a request)
function Test-ProxyHealthy {
    try { (Invoke-RestMethod "http://127.0.0.1:$proxyPort/health" -TimeoutSec 2).status -eq 'ok' } catch { $false }
}

$startTime = Get-Date
while (-not (Test-ProxyHealthy)) {
    if ((Get-Date) -gt ($startTime.AddSeconds(180))) {
        throw "Proxy server failed to start within 180 seconds"
    }
    Start-Sleep -Seconds 1
}

Write-Host "Proxy server is ready on port $proxyPort"