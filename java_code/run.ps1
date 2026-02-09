# Run the Java pipeline web app (Jetty on port 8080).
# Java and Maven are downloaded automatically if missing (Windows x64 / Linux x64).

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# OS detection: PowerShell Core has $IsWindows; fallback for Windows PowerShell
$IsWindowsEnv = if ($null -ne $env:IsWindows) { $env:IsWindows -eq "True" } else { $IsWindows }
if ($null -eq $IsWindowsEnv) {
    $IsWindowsEnv = [System.Environment]::OSVersion.Platform -eq "Win32NT"
}
$JDK_BASE = "jdk-17.0.13%2B11"
$JDK_RELEASE_URL = "https://github.com/adoptium/temurin17-binaries/releases/download/$JDK_BASE"

# Load .env if present
if (Test-Path .env) {
    Get-Content .env | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $line = $line -replace "^export\s+", ""
            if ($line -match "^([^=]+)=(.*)$") {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
    }
}

$MAVEN_VERSION = "3.9.6"
$MAVEN_CACHE = if ($env:MAVEN_CACHE) { $env:MAVEN_CACHE } else { Join-Path $PSScriptRoot ".mvn-cache" }
$MAVEN_HOME = Join-Path $MAVEN_CACHE "apache-maven-$MAVEN_VERSION"
$MAVEN_ZIP = "apache-maven-$MAVEN_VERSION-bin.zip"
$MAVEN_URL = "https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/$MAVEN_ZIP"

$JDK_VERSION = "17.0.13+11"
$JDK_CACHE = if ($env:JDK_CACHE) { $env:JDK_CACHE } else { Join-Path $PSScriptRoot ".jdk-cache" }
if ($IsWindowsEnv) {
    $JDK_ZIP = "OpenJDK17U-jdk_x64_windows_hotspot_17.0.13_11.zip"
} else {
    $JDK_ZIP = "OpenJDK17U-jdk_x64_linux_hotspot_17.0.13_11.tar.gz"
}
$JDK_URL = "$JDK_RELEASE_URL/$JDK_ZIP"

# Per-OS paths: Windows uses bin\java.exe / bin\mvn.cmd, Linux uses bin/java and bin/mvn
$JAVA_EXE = if ($IsWindowsEnv) { "java.exe" } else { "java" }
$MVN_SCRIPT = if ($IsWindowsEnv) { "mvn.cmd" } else { "mvn" }

function Ensure-Java {
    # On Linux, ignore any java that lives under our cache (could be a leftover Windows JDK)
    $foundJava = Get-Command java -ErrorAction SilentlyContinue
    if ($foundJava) {
        if ($IsWindowsEnv) { return }
        $javaSrc = $foundJava.Source
        $cacheNorm = $JDK_CACHE -replace '\\', '/'
        $srcNorm = $javaSrc -replace '\\', '/'
        if (-not $javaSrc -or $srcNorm -notlike "*$cacheNorm*") { return }
    }
    # On Linux, remove any cached JDK that doesn't have bin/java (i.e. Windows build)
    if (-not $IsWindowsEnv) {
        Get-ChildItem -Path $JDK_CACHE -Directory -Filter "jdk*" -ErrorAction SilentlyContinue | ForEach-Object {
            $binJavaPath = Join-Path $_.FullName (Join-Path "bin" "java")
            if (-not (Test-Path $binJavaPath)) { Remove-Item $_.FullName -Recurse -Force }
        }
    }
    $binJava = Join-Path "bin" $JAVA_EXE
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME $binJava))) {
        $env:PATH = (Join-Path $env:JAVA_HOME "bin") + [IO.Path]::PathSeparator + $env:PATH
        return
    }
    $jdkDir = Get-ChildItem -Path $JDK_CACHE -Directory -Filter "jdk*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jdkDir -and (Test-Path (Join-Path $jdkDir.FullName $binJava))) {
        $env:JAVA_HOME = $jdkDir.FullName
        $env:PATH = (Join-Path $jdkDir.FullName "bin") + [IO.Path]::PathSeparator + $env:PATH
        return
    }
    Write-Host "Java not found. Downloading Eclipse Temurin 17 to $JDK_CACHE ..."
    New-Item -ItemType Directory -Force -Path $JDK_CACHE | Out-Null
    # On Linux, remove any existing (e.g. Windows) JDK dir so we get the correct OS build
    if (-not $IsWindowsEnv) {
        Get-ChildItem -Path $JDK_CACHE -Directory -Filter "jdk*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    }
    $archivePath = Join-Path $JDK_CACHE $JDK_ZIP
    try {
        Invoke-WebRequest -Uri $JDK_URL -OutFile $archivePath -UseBasicParsing
    } catch {
        Write-Error "Failed to download JDK: $_"
    }
    Write-Host "Extracting JDK ..."
    if ($IsWindowsEnv) {
        Expand-Archive -Path $archivePath -DestinationPath $JDK_CACHE -Force
    } else {
        & tar -xzf $archivePath -C $JDK_CACHE
        if ($LASTEXITCODE -ne 0) { Write-Error "JDK extraction failed (tar)." }
    }
    Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    $jdkDir = Get-ChildItem -Path $JDK_CACHE -Directory -Filter "jdk*" | Select-Object -First 1
    if (-not $jdkDir -or -not (Test-Path (Join-Path $jdkDir.FullName $binJava))) {
        Write-Error "JDK extraction failed."
    }
    $env:JAVA_HOME = $jdkDir.FullName
    $env:PATH = (Join-Path $jdkDir.FullName "bin") + [IO.Path]::PathSeparator + $env:PATH
    Write-Host "Java ready."
}

function Ensure-Maven {
    if (Get-Command mvn -ErrorAction SilentlyContinue) { return }
    $mvnExe = Join-Path (Join-Path $MAVEN_HOME "bin") $MVN_SCRIPT
    if (Test-Path $mvnExe) {
        $env:PATH = (Join-Path $MAVEN_HOME "bin") + [IO.Path]::PathSeparator + $env:PATH
        return
    }
    Write-Host "Maven not found. Downloading Maven $MAVEN_VERSION to $MAVEN_CACHE ..."
    New-Item -ItemType Directory -Force -Path $MAVEN_CACHE | Out-Null
    $zipPath = Join-Path $MAVEN_CACHE $MAVEN_ZIP
    try {
        Invoke-WebRequest -Uri $MAVEN_URL -OutFile $zipPath -UseBasicParsing
    } catch {
        Write-Error "Failed to download Maven: $_"
    }
    Write-Host "Extracting Maven ..."
    Expand-Archive -Path $zipPath -DestinationPath $MAVEN_CACHE -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $mvnExe)) {
        Write-Error "Maven extraction failed."
    }
    $env:PATH = (Join-Path $MAVEN_HOME "bin") + [IO.Path]::PathSeparator + $env:PATH
    Write-Host "Maven ready."
}

Ensure-Java
Ensure-Maven

Write-Host "Running mvn clean..."
& mvn clean -q
Write-Host "Starting pipeline at http://localhost:8080/"
Write-Host "Press Ctrl+C to stop."
& mvn jetty:run
