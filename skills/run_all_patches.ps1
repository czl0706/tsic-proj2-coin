$ErrorActionPreference = "Continue"
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$GOWIN_HOME = "C:\Gowin\Gowin_V1.9.11.03_Education_x64"
$GW_SH = "$GOWIN_HOME\IDE\bin\gw_sh.exe"

$RepoRoot = $PSScriptRoot | Split-Path -Parent
$PatchDir = Join-Path $RepoRoot "skills\patches"
$FsDir = Join-Path $RepoRoot "skills\fs"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Set-Location $RepoRoot

if (-not (Test-Path $GW_SH)) {
    Write-Host "Gowin shell not found: $GW_SH"
    exit 1
}

if (-not (Test-Path $PatchDir)) {
    Write-Host "Patch directory not found: $PatchDir"
    exit 1
}

New-Item -ItemType Directory -Path $FsDir -Force | Out-Null
Get-ChildItem -Path $FsDir -Filter "*.fs" -File | Remove-Item -Force

$PatchFiles = Get-ChildItem -Path $PatchDir -Filter "*.patch" -File | Sort-Object Name

if ($PatchFiles.Count -eq 0) {
    Write-Host "No patch files found under: $PatchDir"
    exit 1
}

$BaseDiffArgs = @("diff", "HEAD", "--", ".", ":(exclude)skills/patches", ":(exclude)skills/fs", ":(exclude)bin", ":(exclude)fs")
$BaseDiff = @(& git @BaseDiffArgs)
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to read base working tree diff."
    exit 1
}

function Get-ProjectFile {
    param([string]$Root)

    foreach ($Candidate in @("hdmi_coin.prj", "hdmi_coin.gprj")) {
        $CandidatePath = Join-Path $Root $Candidate
        if (Test-Path $CandidatePath) {
            return $CandidatePath
        }
    }

    return $null
}

function Invoke-GowinBuild {
    param([string]$WorktreePath)

    $ProjectFile = Get-ProjectFile -Root $WorktreePath
    if (-not $ProjectFile) {
        Write-Host "Project file not found in: $WorktreePath"
        return 1
    }

    $ProjectFileGw = $ProjectFile -replace "\\", "/"
    $Tcl = @"
open_project "$ProjectFileGw"
run all
run close
"@

    Push-Location $WorktreePath
    try {
        $GowinOutput = @($Tcl | & $GW_SH | ForEach-Object {
            $Line = $_.ToString()
            Write-Host $Line
            $Line
        })
        $GowinExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $HasGowinError = $GowinOutput | Select-String -Pattern '\bERROR\s*\(' -Quiet
    if ($GowinExitCode -ne 0 -or $HasGowinError) {
        return [Math]::Max($GowinExitCode, 1)
    }

    return 0
}

$Failures = @()
$BuiltFiles = @()

foreach ($Patch in $PatchFiles) {
    $PatchName = [System.IO.Path]::GetFileNameWithoutExtension($Patch.Name)
    $WorktreePath = Join-Path $env:TEMP ("hdmi_coin_wt_" + $PatchName + "_" + $Timestamp)

    Write-Host "==== [$PatchName] start ===="

    try {
        if (Test-Path $WorktreePath) {
            $ResolvedWorktree = [System.IO.Path]::GetFullPath($WorktreePath)
            $ResolvedTemp = [System.IO.Path]::GetFullPath($env:TEMP)
            if (-not $ResolvedWorktree.StartsWith($ResolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove path outside temp: $ResolvedWorktree"
            }
            Remove-Item -LiteralPath $WorktreePath -Recurse -Force
        }

        git worktree add --detach "$WorktreePath" HEAD | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "git worktree add failed"
        }

        Push-Location $WorktreePath
        try {
            if ($BaseDiff.Count -gt 0) {
                $BaseDiff | git apply --ignore-whitespace
                if ($LASTEXITCODE -ne 0) {
                    throw "base working tree diff apply failed"
                }
            }

            git apply --ignore-whitespace "$($Patch.FullName)"
            if ($LASTEXITCODE -ne 0) {
                throw "patch apply failed"
            }

            $BuildExit = Invoke-GowinBuild -WorktreePath $WorktreePath
            if ($BuildExit -ne 0) {
                throw "Gowin build failed (exit $BuildExit)"
            }

            $PnrDir = Join-Path $WorktreePath "impl\pnr"
            if (-not (Test-Path $PnrDir)) {
                throw "impl\pnr not found"
            }

            $FsCandidate = Get-ChildItem -Path $PnrDir -Filter "*.fs" -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if (-not $FsCandidate) {
                throw "no .fs bitstream artifact"
            }

            $DstName = "hdmi_coin_${PatchName}.fs"
            $DstPath = Join-Path $FsDir $DstName
            Move-Item -Path $FsCandidate.FullName -Destination $DstPath -Force
            $BuiltFiles += $DstName
        }
        finally {
            Pop-Location
        }

        Write-Host "==== [$PatchName] OK ===="
    }
    catch {
        $Message = $_.Exception.Message
        $Failures += "${PatchName}: $Message"
        Write-Host "==== [$PatchName] FAIL: $Message ===="
    }
    finally {
        try {
            git worktree remove --force "$WorktreePath" | Out-Null
        }
        catch {
        }
    }
}

Write-Host ""
Write-Host "Generated .fs files:"
foreach ($BuiltFile in $BuiltFiles) {
    Write-Host "  skills\fs\$BuiltFile"
}

if ($Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Failures:"
    foreach ($Failure in $Failures) {
        Write-Host "  $Failure"
    }
    exit 1
}

Write-Host ""
Write-Host "Done. Bitstreams are in: $FsDir"
