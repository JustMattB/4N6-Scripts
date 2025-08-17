[CmdletBinding()]
param(
# THE PATH WHERE THE DB IS
    [Parameter(Mandatory=$false)]
    [string]$DbDir = "FULL PATH TO THE DB FOLDER",
# THE DB NAME
    [Parameter(Mandatory=$false)]
    [string]$DbFile = "RDS_2025.03.1_ios.db",  # If blank, the newest *.db in DbDir is used.
# YOUR OUTPUT DIR
    [Parameter(Mandatory=$false)]
    [string]$OutDir = "FULL PATH TO OURPUT FOLDER",
# PATH TO THE SQLITE3 APPLCIATION. Download it from sqlite.org/downloads.html 
    [Parameter(Mandatory=$false)]
    [string]$Sqlite3 = "d:\sqlite-tools-win-x64-3500400\sqlite3.exe"   # Path to sqlite3.exe. If blank, will try PATH.
)

function Get-Sqlite3Path {
    param([string]$Override)
    if ($Override -and (Test-Path $Override)) { return (Resolve-Path $Override).Path }
    $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "sqlite3.exe not found. Install SQLite tools and ensure sqlite3.exe is on PATH or provide -Sqlite3 path."
}

function Get-DbPath {
    param([string]$Dir, [string]$File)
    if ($File) {
        $p = Join-Path $Dir $File
        if (-not (Test-Path $p)) { throw "Database file not found: $p" }
        return (Resolve-Path $p).Path
    }
    $candidate = Get-ChildItem -Path $Dir -Filter *.db -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $candidate) { throw "No *.db file found in $Dir" }
    return $candidate.FullName
}

function Invoke-SqliteCsv {
    param(
        [string]$Sqlite3Path,
        [string]$DbPath,
        [string]$SqlScript,   # Body: .mode/.headers/.output + SELECT
        [string]$WorkDir
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Sqlite3Path
    $psi.Arguments = '"' + $DbPath + '"'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $WorkDir
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.WriteLine($SqlScript)
    $p.StandardInput.Close()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        throw "sqlite3 failed (exit $($p.ExitCode)): $stderr"
    }
}

function Write-HeaderAndAppend {
    param(
        [string]$HeaderLine,
        [string]$InputPath,
        [string]$OutputPath
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    # Write header
    $sw = New-Object System.IO.StreamWriter($OutputPath, $false, $utf8NoBom)
    $sw.WriteLine($HeaderLine)
    $sw.Flush()
    # Append transformed content (replace """ with ")
    $sr = New-Object System.IO.StreamReader($InputPath)
    try {
        while (-not $sr.EndOfStream) {
            $line = $sr.ReadLine()
            if ($null -ne $line) {
                $line = $line -replace '"""','"'
                $sw.WriteLine($line)
            }
        }
    }
    finally {
        $sr.Close()
        $sw.Close()
    }
}

# Resolve paths
$Sqlite3Path = Get-Sqlite3Path -Override $Sqlite3
$DbPath = Get-DbPath -Dir $DbDir -File $DbFile
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$tempDir = Join-Path $OutDir "_temp"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Host "Using sqlite3: $Sqlite3Path"
Write-Host "Using database: $DbPath"
Write-Host "Output directory: $OutDir"

# Utility to normalize path for sqlite3 .output (prefer forward slashes)
function To-SqlPath([string]$p) { return ($p -replace '\\','/') }

# --------------------------
# NSRLFile.txt
# --------------------------
$nsrlFileTmp = Join-Path $tempDir "NSRLFile-output.txt"
$nsrlFileOut = Join-Path $OutDir "NSRLFile.txt"
$nsrlFileOutSql = To-SqlPath $nsrlFileTmp
$nsrlFileSql = @"
.mode csv
.headers off
.output "$nsrlFileOutSql"
SELECT
  '"' || sha1 || '"',
  '"' || md5 || '"',
  '"' || crc32 || '"',
  '"' || REPLACE(file_name,'"','') || '"',
  file_size,
  package_id,
  '"' || 0 || '"',
  '""'
FROM FILE
ORDER BY sha1;
.output stdout
"@
Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $nsrlFileSql -WorkDir (Split-Path $DbPath)
Write-HeaderAndAppend -HeaderLine '"SHA-1","MD5","CRC32","FileName","FileSize","ProductCode","OpSystemCode","SpecialCode"' `
    -InputPath $nsrlFileTmp -OutputPath $nsrlFileOut
Remove-Item $nsrlFileTmp -ErrorAction SilentlyContinue

# --------------------------
# NSRLMfg.txt
# --------------------------
$mfgTmp = Join-Path $tempDir "NSRLMfg-output.txt"
$mfgOut = Join-Path $OutDir "NSRLMfg.txt"
$mfgOutSql = To-SqlPath $mfgTmp
$mfgSql = @"
.mode csv
.headers off
.output "$mfgOutSql"
SELECT
  manufacturer_id,
  '"' || REPLACE(name,'"','') || '"'
FROM MFG
ORDER BY manufacturer_id;
.output stdout
"@
Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $mfgSql -WorkDir (Split-Path $DbPath)
Write-HeaderAndAppend -HeaderLine '"MfgCode","MfgName"' -InputPath $mfgTmp -OutputPath $mfgOut
Remove-Item $mfgTmp -ErrorAction SilentlyContinue

# --------------------------
# NSRLOS.txt
# --------------------------
$osTmp = Join-Path $tempDir "NSRLOS-output.txt"
$osOut = Join-Path $OutDir "NSRLOS.txt"
$osOutSql = To-SqlPath $osTmp
$osSql = @"
.mode csv
.headers off
.output "$osOutSql"
SELECT
  operating_system_id,
  '"' || REPLACE(name,'"','') || '"',
  '"' || REPLACE(version,'"','') || '"',
  manufacturer_id
FROM OS
ORDER BY operating_system_id;
.output stdout
"@
Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $osSql -WorkDir (Split-Path $DbPath)
Write-HeaderAndAppend -HeaderLine '"OpSystemCode","OpSystemName","OpSystemVersion","MfgCode"' -InputPath $osTmp -OutputPath $osOut
Remove-Item $osTmp -ErrorAction SilentlyContinue

# --------------------------
# NSRLProd.txt
# --------------------------
$prodTmp = Join-Path $tempDir "NSRLProd-output.txt"
$prodOut = Join-Path $OutDir "NSRLProd.txt"
$prodOutSql = To-SqlPath $prodTmp
$prodSql = @"
.mode csv
.headers off
.output "$prodOutSql"
SELECT
  package_id,
  '"' || REPLACE(name,'"','') || '"',
  '"' || REPLACE(version,'"','') || '"',
  operating_system_id,
  manufacturer_id,
  '"' || REPLACE(language,'"','') || '"',
  '"' || REPLACE(application_type,'"','') || '"'
FROM PKG
ORDER BY package_id;
.output stdout
"@
Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $prodSql -WorkDir (Split-Path $DbPath)
Write-HeaderAndAppend -HeaderLine '"ProductCode","ProductName","ProductVersion","OpSystemCode","MfgCode","Language","ApplicationType"' `
    -InputPath $prodTmp -OutputPath $prodOut
Remove-Item $prodTmp -ErrorAction SilentlyContinue

# Cleanup temp
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Done. Files written to: $OutDir" -ForegroundColour Green -Backgroundcolour Black


