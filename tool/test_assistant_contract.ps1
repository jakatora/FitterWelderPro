[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $BackendDir,
    [Parameter(Mandatory = $true)][string] $FlutterExe
)

$ErrorActionPreference = 'Stop'
$backend = (Resolve-Path -LiteralPath $BackendDir).Path
$flutter = (Resolve-Path -LiteralPath $FlutterExe).Path
$fixture = Join-Path $backend 'test\helpers\flutter-contract-server.js'
if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
    throw "Missing fake-model backend fixture: $fixture"
}
$node = (Get-Command node -CommandType Application | Select-Object -First 1).Source
$app = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$process = [System.Diagnostics.Process]::new()
$process.StartInfo.FileName = $node
$process.StartInfo.WorkingDirectory = $backend
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.CreateNoWindow = $true
$process.StartInfo.RedirectStandardInput = $true
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.ArgumentList.Add('--disable-warning=ExperimentalWarning')
$process.StartInfo.ArgumentList.Add($fixture)
$oldServer = $env:FWP_CONTRACT_SERVER
$exitCode = 1
$cleanupFailed = $false
$cleanupError = ''
$started = $false
try {
    if (-not $process.Start()) { throw 'Could not start the local fixture.' }
    $started = $true
    $lineTask = $process.StandardOutput.ReadLineAsync()
    if (-not $lineTask.Wait(15000)) { throw 'Local fixture did not start in time.' }
    $line = $lineTask.Result
    if ($line -notmatch '^FWP_TEST_SERVER=(http://127\.0\.0\.1:[0-9]+)$') {
        throw "Unexpected local fixture response: $line"
    }
    # Drain output while the Flutter process runs to prevent a full pipe from
    # blocking the server before it can read the shutdown command.
    $remainingTask = $process.StandardOutput.ReadToEndAsync()
    $env:FWP_CONTRACT_SERVER = $Matches[1]
    Push-Location $app
    try {
        & $flutter test --no-pub --reporter expanded test/assistant/backend_contract_integration_test.dart
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    $env:FWP_CONTRACT_SERVER = $oldServer
    if ($started -and -not $process.HasExited) {
        try {
            $process.StandardInput.WriteLine('stop')
            $process.StandardInput.Flush()
            if (-not $process.WaitForExit(10000)) { throw 'Fixture did not stop.' }
            $remaining = $remainingTask.Result
            if ($remaining -notmatch '(?m)^FWP_TEST_CLEANUP_OK\r?$') {
                throw 'Fixture did not confirm removal of the temporary database.'
            }
        } catch {
            $cleanupFailed = $true
            $cleanupError = $_.Exception.Message
            if (-not $process.HasExited) { $process.Kill() }
        }
    }
    if ($started -and $process.HasExited -and $process.ExitCode -ne 0) { $cleanupFailed = $true }
    $process.Dispose()
}
if ($cleanupFailed) { throw "Local fixture cleanup failed: $cleanupError. Inspect temporary test files." }
exit $exitCode
