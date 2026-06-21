param(
    [string]$InputDir = "png",
    [string]$OutputDir = "mem"
)

Add-Type -AssemblyName System.Drawing

function Resolve-LocalPath {
    param([string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return Join-Path $PSScriptRoot $PathValue
}

$InputPath = Resolve-LocalPath $InputDir
$OutputPath = Resolve-LocalPath $OutputDir

if (!(Test-Path $InputPath -PathType Container)) {
    throw "Input folder not found: $InputPath"
}

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$pngFiles = Get-ChildItem -Path $InputPath -Filter "*.png" -File | Sort-Object Name

if ($pngFiles.Count -eq 0) {
    throw "No .png files found in: $InputPath"
}

$convertedCount = 0

foreach ($png in $pngFiles) {
    $bmp = [System.Drawing.Bitmap]::new($png.FullName)
    $width = $bmp.Width
    $height = $bmp.Height
    $memPath = Join-Path $OutputPath ($png.BaseName + ".mem")
    $writer = [System.IO.StreamWriter]::new($memPath, $false, [System.Text.Encoding]::ASCII)

    try {
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $color = $bmp.GetPixel($x, $y)

                $r = [int]$color.R
                $g = [int]$color.G
                $b = [int]$color.B

                if ([int]$color.A -eq 0) {
                    $r = 0
                    $g = 0
                    $b = 0
                }

                $rgb565 = (($r -shr 3) -shl 11) -bor (($g -shr 2) -shl 5) -bor ($b -shr 3)
                $writer.WriteLine("{0:X4}" -f $rgb565)
            }
        }
    }
    finally {
        $writer.Dispose()
        $bmp.Dispose()
    }

    $convertedCount++
    Write-Host "$($png.Name) -> $([System.IO.Path]::GetFileName($memPath)) ($width x $height, RGB565)"
}

Write-Host "Converted $convertedCount PNG file(s)."
Write-Host "Input dir : $InputPath"
Write-Host "Output dir: $OutputPath"
