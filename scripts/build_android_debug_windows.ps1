# Builds a debug APK using the SDK explicitly selected for this project.
# Windows PipeImpl may fail to connect a Unix-domain socket in this environment.
# A deliberately missing Unix socket directory makes Java use TCP for the pipe.
[CmdletBinding()]
param(
    [string]$FlutterPath = (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw "Flutter SDK executable not found: $FlutterPath"
}

$projectDirectory = Split-Path -Parent $PSScriptRoot
$missingSocketDirectory = Join-Path ([IO.Path]::GetTempPath()) (
    'fwp-no-unix-socket-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $missingSocketDirectory) {
    throw 'The fallback socket directory must not exist.'
}

$previousJavaOptions = [Environment]::GetEnvironmentVariable('JAVA_TOOL_OPTIONS', 'Process')
$fallbackOption = '-Djdk.net.unixdomain.tmpdir="' + $missingSocketDirectory + '"'
try {
    $env:JAVA_TOOL_OPTIONS = (@($previousJavaOptions, $fallbackOption) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    Push-Location -LiteralPath $projectDirectory
    try {
        & $FlutterPath build apk --debug --no-pub
        if ($LASTEXITCODE -ne 0) {
            throw "Android debug build failed (exit $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    [Environment]::SetEnvironmentVariable('JAVA_TOOL_OPTIONS', $previousJavaOptions, 'Process')
}
