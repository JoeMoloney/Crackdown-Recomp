<#
.SYNOPSIS
  Build and install the pinned Himdo ReXGlue source into tools\rexglue\himdo\win-amd64.
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'build-common.ps1')
$Baseline = Read-KeyValueFile (Join-Path $Root 'patches\rexglue-sdk\baseline.env')
$Src = Join-Path $Root 'out\rexglue-himdo-sdk-src'
$Sdk = Join-Path $Root 'tools\rexglue\himdo\win-amd64'
$Patch = Join-Path $Root 'patches\rexglue-sdk\1105-himdo-port.patch'

function Invoke-Native([string]$What, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE) { throw "$What failed ($LASTEXITCODE)" }
}

$toolchain = Get-BuildToolchain
$savedEnv = Save-BuildEnvironment
try {
    Import-BuildEnvironment $toolchain
    if (-not (Test-Path -LiteralPath (Join-Path $Src '.git'))) {
        New-Item -ItemType Directory -Force (Split-Path $Src) | Out-Null
        Invoke-Native 'ReXGlue clone' { git clone --no-checkout $Baseline['SDK_REPO'] $Src }
    }
    Invoke-Native 'ReXGlue fetch' { git -C $Src fetch --depth 1 origin $Baseline['SDK_COMMIT'] }
    Invoke-Native 'ReXGlue checkout' { git -C $Src checkout --detach $Baseline['SDK_COMMIT'] }
    $commit = "$(git -C $Src rev-parse HEAD)".Trim()
    if ($commit -ne $Baseline['SDK_COMMIT']) { throw "ReXGlue source is $commit, expected $($Baseline['SDK_COMMIT'])" }
    Invoke-Native 'ReXGlue submodule update' { git -C $Src submodule update --init --recursive --jobs 8 }

    & git -C $Src apply --reverse --check $Patch *> $null
    if ($LASTEXITCODE -ne 0) {
        & git -C $Src diff --quiet
        $worktreeDirty = $LASTEXITCODE -ne 0
        & git -C $Src diff --cached --quiet
        if ($worktreeDirty -or $LASTEXITCODE -ne 0) { throw "$Src has local changes unrelated to the migration patch" }
        Invoke-Native 'Himdo migration patch check' { git -C $Src apply --check $Patch }
        Invoke-Native 'Himdo migration patch' { git -C $Src apply $Patch }
    } else {
        Write-Host 'Himdo migration patch is already applied.'
    }

    Invoke-Native 'ReXGlue configure' {
        & $toolchain.CMake --preset win-amd64 -S $Src `
            "-DCMAKE_C_COMPILER:FILEPATH=$($toolchain.Clang)" `
            "-DCMAKE_CXX_COMPILER:FILEPATH=$($toolchain.ClangXX)" `
            "-DCMAKE_LINKER:FILEPATH=$($toolchain.LldLink)" `
            "-DCMAKE_MAKE_PROGRAM:FILEPATH=$($toolchain.Ninja)" `
            -DREXGLUE_ENABLE_FIDELITYFX=OFF
    }
    Invoke-Native 'ReXGlue build' {
        & $toolchain.CMake --build (Join-Path $Src 'out\build\win-amd64') --config Release `
            --target rexruntime rexgpu-xenos rexglue SDL3_test disasm --parallel
    }
    Invoke-Native 'ReXGlue install' {
        & $toolchain.CMake --install (Join-Path $Src 'out\build\win-amd64') --config Release --prefix $Sdk
    }
    $config = Join-Path $Sdk 'lib\cmake\rexglue\rexglueConfig.cmake'
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "SDK install is missing $config" }
    Write-Host "Installed Himdo ReXGlue $commit at $Sdk"
} finally {
    Restore-BuildEnvironment $savedEnv
}
