[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $AppDir,
    [Parameter(Mandatory = $true)][string] $CacheDir
)

$ErrorActionPreference = 'Stop'
$app = (Resolve-Path -LiteralPath $AppDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $app 'FitterWelderPro.exe') -PathType Leaf)) {
    throw 'AppDir must contain FitterWelderPro.exe.'
}
$cache = (Resolve-Path -LiteralPath $CacheDir).Path
if (-not (Test-Path -LiteralPath $cache -PathType Container)) {
    throw 'CacheDir must be an existing directory.'
}

# Digests pin bytes downloaded from the official HTTPS origins. They are not
# publisher signatures; review and update them intentionally when upgrading.
$assets = @(
    @{ Name = 'vosk-win64-0.3.45.zip'; Sha = 'F1DCC9CCA460630F81EA8F71794F69C80BED6556D2A4E6237B5785E1D2DFF34B';
       Url = 'https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-win64-0.3.45.zip' },
    @{ Name = 'vosk-model-small-pl-0.22.zip'; Sha = 'C4CD16498EA544F446F9E9A55CBD602B71CFE5A2B6F2B0834D81E1B6FCE15F0D';
       Url = 'https://alphacephei.com/vosk/models/vosk-model-small-pl-0.22.zip' },
    @{ Name = 'vosk-model-small-en-us-0.15.zip'; Sha = '30F26242C4EB449F948E42CB302DD7A686CB29A3423A8367F99FF41780942498';
       Url = 'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip' }
)
foreach ($asset in $assets) {
    $file = Join-Path $cache $asset.Name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        $partial = Join-Path $cache ('.fwp-download-' + [Guid]::NewGuid().ToString('N'))
        try {
            Invoke-WebRequest -Uri $asset.Url -OutFile $partial
            if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $asset.Sha) {
                throw "Unexpected checksum for $($asset.Name)."
            }
            Move-Item -LiteralPath $partial -Destination $file
        } finally {
            if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force }
        }
    }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $asset.Sha) {
        throw "Cached file $($asset.Name) has an unexpected checksum."
    }
}

$modelNames = @('vosk-model-small-pl-0.22', 'vosk-model-small-en-us-0.15')
$modelsParent = Join-Path $app 'data\offline_voice'
foreach ($modelName in $modelNames) {
    if (Test-Path -LiteralPath (Join-Path $modelsParent $modelName)) {
        throw 'The model destination already exists; refusing to overwrite it.'
    }
}
$libraries = @('libvosk.dll', 'libgcc_s_seh-1.dll', 'libstdc++-6.dll', 'libwinpthread-1.dll')
foreach ($name in $libraries) {
    if (Test-Path -LiteralPath (Join-Path $app $name)) {
        throw "The application already contains $name; refusing to overwrite it."
    }
}

$stage = Join-Path $cache ('.fwp-voice-stage-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    Expand-Archive -LiteralPath (Join-Path $cache 'vosk-win64-0.3.45.zip') -DestinationPath $stage
    foreach ($modelName in $modelNames) {
        Expand-Archive -LiteralPath (Join-Path $cache "$modelName.zip") -DestinationPath $stage
    }
    $release = Join-Path $stage 'vosk-win64-0.3.45'
    foreach ($name in $libraries) {
        if (-not (Test-Path -LiteralPath (Join-Path $release $name) -PathType Leaf)) {
            throw "Missing library $name."
        }
    }
    foreach ($modelName in $modelNames) {
        $model = Join-Path $stage $modelName
        foreach ($name in @('am\final.mdl', 'conf\model.conf', 'graph\Gr.fst', 'graph\HCLr.fst', 'ivector\final.ie')) {
            if (-not (Test-Path -LiteralPath (Join-Path $model $name) -PathType Leaf)) {
                throw "Missing model component $modelName/$name."
            }
        }
    }
    New-Item -ItemType Directory -Force -Path $modelsParent | Out-Null
    foreach ($modelName in $modelNames) {
        Copy-Item -LiteralPath (Join-Path $stage $modelName) -Destination (Join-Path $modelsParent $modelName) -Recurse
    }
    foreach ($name in $libraries) {
        Copy-Item -LiteralPath (Join-Path $release $name) -Destination (Join-Path $app $name)
    }
    Write-Output 'Offline voice assets prepared for Windows. The application feature remains disabled until verified.'
} finally {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    $resolvedCache = [IO.Path]::GetFullPath($cache).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedStage.StartsWith($resolvedCache, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to remove staging directory outside CacheDir.'
    }
    if (Test-Path -LiteralPath $resolvedStage -PathType Container) {
        $stageItem = Get-Item -LiteralPath $resolvedStage -Force
        if ($stageItem.LinkType) { throw 'Refusing to remove a linked staging directory.' }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
