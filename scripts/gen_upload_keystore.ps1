$ErrorActionPreference = 'Stop'

$storePass = (([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')).Substring(0, 32))
$keyPass = $storePass

$keystorePath = Join-Path $PSScriptRoot '..\upload-keystore.jks'
$keystorePath = (Resolve-Path $keystorePath).Path

if (Test-Path $keystorePath) {
  Remove-Item $keystorePath -Force
}

# Generate upload keystore
& keytool -genkeypair -v `
  -keystore $keystorePath `
  -storetype JKS `
  -storepass $storePass `
  -alias upload `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -keypass $keyPass `
  -dname "CN=Fitter Welder Pro, OU=Startklaar, O=Startklaar, L=, ST=, C=PL" | Out-Null

# Write android/key.properties (gitignored)
$keyPropsPath = Join-Path $PSScriptRoot '..\android\key.properties'
$keyPropsPath = (Resolve-Path $keyPropsPath).Path

@(
  'storeFile=../upload-keystore.jks',
  "storePassword=$storePass",
  "keyPassword=$keyPass",
  'keyAlias=upload'
) | Set-Content -Encoding ASCII $keyPropsPath

"OK: upload-keystore.jks generated"
"OK: android/key.properties populated (open it to see passwords)"
"Password length: $($storePass.Length)"
