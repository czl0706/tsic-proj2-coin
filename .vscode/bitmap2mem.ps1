param(
    [string]$InputDir = "bitmap",
    [string]$OutputFile = "src\assets\font.mem"
)

# Packs the 6x12 ASCII digit bitmaps in bitmap/0.txt .. 9.txt into a 1-bit
# font ROM for ui_layer. Each glyph row becomes a 6-bit word (MSB = leftmost
# column, i.e. bit 5 = column 0), so the .mem hex reads left-to-right like the
# glyph. Each digit is padded from 12 to 16 rows so the Verilog address can be
# {digit[3:0], src_y[3:0]} with no multiply. Output: 160 lines x 2 hex.

$COLS = 6
$ROWS = 12
$PADDED_ROWS = 16
$DIGITS = 10

$ROOT = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return Join-Path $ROOT $PathValue
}

$InputPath = Resolve-LocalPath $InputDir
$OutputPath = Resolve-LocalPath $OutputFile

if (!(Test-Path $InputPath -PathType Container)) {
    throw "Input folder not found: $InputPath"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null

$writer = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.Encoding]::ASCII)

try {
    for ($d = 0; $d -lt $DIGITS; $d++) {
        $txtPath = Join-Path $InputPath ("{0}.txt" -f $d)
        if (!(Test-Path $txtPath -PathType Leaf)) {
            throw "Missing glyph file: $txtPath"
        }
        $lines = @(Get-Content -Path $txtPath)

        for ($r = 0; $r -lt $PADDED_ROWS; $r++) {
            $word = 0
            if ($r -lt $ROWS -and $r -lt $lines.Count) {
                $line = $lines[$r]
                for ($c = 0; $c -lt $COLS; $c++) {
                    if ($c -lt $line.Length -and $line[$c] -eq '#') {
                        $word = $word -bor (1 -shl ($COLS - 1 - $c))
                    }
                }
            }
            $writer.WriteLine("{0:X2}" -f $word)
        }
    }
}
finally {
    $writer.Dispose()
}

Write-Host "Wrote $OutputPath ($($DIGITS * $PADDED_ROWS) lines, ${COLS}-bit words)."
