<#
.SYNOPSIS
    Builds RadioXL's plugin once per supported game build: the newest build's into the main download's
    red4ext/plugins/RadioXL, the older build's into its compatibility download under compat/<build>.

.DESCRIPTION
    RED4ext.SDK fixes its type layouts and the runtime a plugin declares when the plugin is compiled, so
    one DLL serves one game build. Each entry in $Builds names the SDK it compiles against:
      - the current _source/RED4ext.SDK mirror, for the newest game build;
      - an export of that mirror at a fixed commit, for the build before it.
    The export is made with `git archive` into plugin/build/sdk/<commit>/ (gitignored); nothing is written
    inside _source. Every build is named RadioXL.dll: the compatibility download installs over the main
    one's, so one DLL is ever in the plugin folder.

.EXAMPLE
    pwsh -File plugin\build.ps1
#>
$ErrorActionPreference = 'Stop'

$Plugin = $PSScriptRoot
$Mirror = Resolve-Path (Join-Path $Plugin '..\..\..\_source\RED4ext.SDK')
$Root = Join-Path $Plugin '..'
$CMake = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'

# Game build -> the SDK it compiles against and where its DLL ships. A $null commit is the mirror as it is.
$Builds = @(
    @{ Game = '2.5';  Commit = $null;      Dir = 'build';      Ship = 'red4ext\plugins\RadioXL' },
    @{ Game = '2.31'; Commit = 'f9ad5334'; Dir = 'build\2.31'; Ship = 'compat\2.31\red4ext\plugins\RadioXL' }
)

foreach ($b in $Builds) {
    if ($b.Commit) {
        $sdk = Join-Path $Plugin "build\sdk\$($b.Commit)"
        if (-not (Test-Path (Join-Path $sdk 'include\RED4ext\RED4ext.hpp'))) {
            New-Item -ItemType Directory -Force $sdk | Out-Null
            $tar = Join-Path $sdk 'sdk.tar'
            git -C $Mirror archive --format=tar -o $tar $b.Commit include
            if ($LASTEXITCODE -ne 0) { throw "git archive of RED4ext.SDK $($b.Commit) failed" }
            # Windows' own tar: Git's GNU tar reads a drive letter as a remote host.
            & (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $tar -C $sdk
            if ($LASTEXITCODE -ne 0) { throw "extracting RED4ext.SDK $($b.Commit) failed" }
            Remove-Item $tar
        }
        $include = Join-Path $sdk 'include'
    } else {
        $include = Join-Path $Mirror 'include'
    }

    $out = Join-Path $Plugin $b.Dir
    $ship = Join-Path $Root $b.Ship
    Write-Host "== game $($b.Game): RadioXL.dll against $include -> $($b.Ship)" -ForegroundColor Cyan
    & $CMake -S $Plugin -B $out -G 'Visual Studio 17 2022' -A x64 `
        "-DRADIOXL_SDK_INCLUDE=$include" "-DRADIOXL_OUTPUT_NAME=RadioXL" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "configure failed for game $($b.Game)" }
    & $CMake --build $out --config Release
    if ($LASTEXITCODE -ne 0) { throw "build failed for game $($b.Game)" }
    New-Item -ItemType Directory -Force $ship | Out-Null
    Copy-Item (Join-Path $out 'Release\RadioXL.dll') $ship -Force
    Write-Host "   shipped $($b.Ship)\RadioXL.dll" -ForegroundColor Green
}
