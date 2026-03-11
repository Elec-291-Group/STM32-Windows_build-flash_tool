# =============================================================================
# build.ps1 - Generic build & flash script for STM32CubeMX CMake projects
# Usage:
#   .\build.ps1                          # build + convert to BIN (default)
#   .\build.ps1 flash                    # build + flash on default port
#   .\build.ps1 flash -Port COM5         # build + flash on COM5
#   .\build.ps1 clean                    # clean build artifacts
#   .\build.ps1 bin -FlashTool "C:\tools\stm32flash.exe"
# =============================================================================

param(
    [string]$Target    = "bin",
    [string]$Port      = "COM3",
    [string]$Baud      = "115200",
    [string]$FlashTool = "D:\下载\STM32L051\stm32flash\stm32flash.exe"
)

$ErrorActionPreference = "Stop"

# --- Auto-detect project name from CMakeLists.txt ----------------------------
$ProjectRoot = $PSScriptRoot
$CmakeLists  = Get-Content "$ProjectRoot\CMakeLists.txt" -Raw
if ($CmakeLists -match 'set\s*\(\s*CMAKE_PROJECT_NAME\s+([\w_]+)') {
    $ProjectName = $Matches[1]
} else {
    throw "Cannot find CMAKE_PROJECT_NAME in CMakeLists.txt"
}

# --- Derived paths -----------------------------------------------------------
$BuildDir = "$ProjectRoot\build"
$ElfFile  = "$BuildDir\$ProjectName.elf"
$BinFile  = "$BuildDir\$ProjectName.bin"
$ObjCopy  = "arm-none-eabi-objcopy"

# --- Auto-find make.exe ------------------------------------------------------
$Make = (Get-Command make -ErrorAction SilentlyContinue)?.Source
if (-not $Make) {
    $candidates = @(
        "D:\MSYS2\usr\bin\make.exe",
        "D:\Git\usr\bin\make.exe",
        "C:\MSYS2\usr\bin\make.exe",
        "C:\msys64\usr\bin\make.exe"
    )
    $Make = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Make) { throw "make.exe not found. Add MSYS2 usr/bin to PATH." }

# --- Fix MinGW linker temp file issue ----------------------------------------
$TempDir = "$env:USERPROFILE\AppData\Local\Temp\stm32build"
New-Item -ItemType Directory -Force $TempDir | Out-Null
$env:TMP  = $TempDir
$env:TEMP = $TempDir

# --- CMake configure (only when build/Makefile is absent) --------------------
function Invoke-Configure {
    if (-not (Test-Path "$BuildDir\Makefile")) {
        Write-Host "[cmake] Configuring project '$ProjectName'..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force $BuildDir | Out-Null
        Push-Location $BuildDir
        cmake .. -G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=../cmake/gcc-arm-none-eabi.cmake
        if ($LASTEXITCODE -ne 0) { Pop-Location; throw "cmake configure failed" }
        Pop-Location
    }
}

# --- Shared build steps ------------------------------------------------------
function Invoke-Build {
    Invoke-Configure
    Write-Host "[make] Building '$ProjectName'..." -ForegroundColor Cyan
    & $Make -C $BuildDir
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
}

function Invoke-ObjCopy {
    Write-Host "[objcopy] $ProjectName.elf -> $ProjectName.bin" -ForegroundColor Cyan
    & $ObjCopy -O binary $ElfFile $BinFile
}

# --- Targets -----------------------------------------------------------------
switch ($Target) {

    "build" {
        Invoke-Build
        Write-Host "[done] $ElfFile" -ForegroundColor Green
    }

    "bin" {
        Invoke-Build
        Invoke-ObjCopy
        Write-Host "[done] $BinFile" -ForegroundColor Green
    }

    "flash" {
        if (-not (Test-Path $FlashTool)) { throw "stm32flash not found at: $FlashTool" }
        Invoke-Build
        Invoke-ObjCopy
        Write-Host "[flash] Writing to $Port at $Baud baud..." -ForegroundColor Cyan
        & $FlashTool -b $Baud -w $BinFile -v -g 0x08000000 $Port
        if ($LASTEXITCODE -ne 0) { throw "Flash failed" }
        Write-Host "[done] Flash successful" -ForegroundColor Green
    }

    "clean" {
        if (Test-Path $BuildDir) {
            & $Make -C $BuildDir clean
            Remove-Item -Force "$BuildDir\$ProjectName.bin",
                               "$BuildDir\$ProjectName.map" -ErrorAction SilentlyContinue
        }
        Write-Host "[done] Cleaned" -ForegroundColor Green
    }

    default {
        Write-Host "Unknown target: $Target"
        Write-Host "Valid targets: bin (default), build, flash, clean"
    }
}
