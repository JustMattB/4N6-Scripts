############## EXTRACT THE NIST NSRL INFO FROM THE NIST DB AND CREATE MD5 LISTS ##############
############## Requires PowerShell and SQLITE3.exe from sqlite.org ##########################

[CmdletBinding()]
param(
    [string]$DbDir  = "D:\GAD\RDS_2025.03.1_ios\RDS_2025.03.1_ios",
    [string]$DbFile = "RDS_2025.03.1_ios.db",
    [string]$OutDir = "D:\GAD\CNSRL_Output",
    [string]$Sqlite3 = "D:\GAD\sqlite-tools-win-x64-3500400\sqlite3.exe"
)

Write-Host "🚀 Processing NIST NSRL DB to text..." -ForegroundColor green

function Get-Sqlite3Path {
    param([string]$Override)
    if ($Override -and (Test-Path $Override)) { return (Resolve-Path $Override).Path }
    $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "sqlite3.exe not found. Install SQLite tools and ensure it's on PATH or provide -Sqlite3."
}

function Get-DbPath {
    param([string]$Dir, [string]$File)
    if ($File) {
        $p = Join-Path $Dir $File
        if (-not (Test-Path $p)) { throw "Database file not found: $p" }
        return (Resolve-Path $p).Path
    }
    $candidate = Get-ChildItem -Path $Dir -Filter *.db -File -ErrorAction Stop |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $candidate) { throw "No *.db file found in $Dir" }
    return $candidate.FullName
}

function Invoke-SqliteCsv {
    param(
        [string]$Sqlite3Path,
        [string]$DbPath,
        [string]$SqlScript,
        [string]$WorkDir
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Sqlite3Path
    $psi.Arguments = '"' + $DbPath + '"'
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.WorkingDirectory       = $WorkDir
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.WriteLine($SqlScript)
    $p.StandardInput.Close()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "sqlite3 failed (exit $($p.ExitCode)): $stderr" }
}

function To-SqlPath([string]$p) { return ($p -replace '\\','/') }

# Resolve paths
$Sqlite3Path = Get-Sqlite3Path -Override $Sqlite3
$DbPath      = Get-DbPath -Dir $DbDir -File $DbFile
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host "Using sqlite3: $Sqlite3Path"
Write-Host "Using database: $DbPath"
Write-Host "Output directory: $OutDir"

# 1) Full CSV export
$nsrlFileOut    = Join-Path $OutDir "NSRLFile.txt"
$nsrlFileOutSql = To-SqlPath $nsrlFileOut
$nsrlFileSql = @"
.mode csv
.headers on
.output "$nsrlFileOutSql"
SELECT
  sha1 AS "SHA-1",
  md5 AS "MD5",
  crc32 AS "CRC32",
  REPLACE(file_name, '"', '') AS "FileName",
  file_size AS "FileSize",
  package_id AS "ProductCode",
  0 AS "OpSystemCode",
  '' AS "SpecialCode"
FROM FILE
ORDER BY sha1;
.output stdout
"@
Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $nsrlFileSql -WorkDir (Split-Path $DbPath)

# 2) MD5-only
$md5OnlyFile    = Join-Path $OutDir "NSRLFile-MD5-Only.txt"
$md5OnlyFileSql = To-SqlPath $md5OnlyFile
$md5Sql = @"
.mode list
.separator "\n"
.headers off
.output "$md5OnlyFileSql"
SELECT md5
FROM FILE
ORDER BY sha1;
.output stdout
"@
Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $md5Sql -WorkDir (Split-Path $DbPath)

# 3) MD5-only deduplicated
$md5OnlyDedupFile    = Join-Path $OutDir "NSRLFile-MD5-Only-DEDUP.txt"
$md5OnlyDedupFileSql = To-SqlPath $md5OnlyDedupFile
$md5DedupSql = @"
.mode list
.separator "\n"
.headers off
.output "$md5OnlyDedupFileSql"
WITH keyed AS (
  SELECT
    md5,
    LOWER(TRIM(md5)) AS norm_key
  FROM FILE
  WHERE md5 IS NOT NULL AND TRIM(md5) <> ''
)
SELECT md5
FROM keyed
WHERE norm_key IN (
  SELECT norm_key
  FROM keyed
  GROUP BY norm_key
)
GROUP BY norm_key
ORDER BY md5;
.output stdout
"@
Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $md5DedupSql -WorkDir (Split-Path $DbPath)

Write-Host "✅ NIST NSRL extraction completed." -ForegroundColor green -BackgroundColor black
Write-Host "Full file:    $nsrlFileOut" -ForegroundColor green -BackgroundColor black
Write-Host "MD5 Full Hash List From NSRL:     $md5OnlyFile" -ForegroundColor green -BackgroundColor black
Write-Host "MD5 De-Duplicated:     $md5OnlyDedupFile" --ForegroundColor green -BackgroundColor black
Write-Host "Have a nice day" -ForegroundColor green -BackgroundColor black

    $candidate = Get-ChildItem -Path $Dir -Filter *.db -File -ErrorAction Stop |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $candidate) { throw "No *.db file found in $Dir" }
    return $candidate.FullName
}

function Invoke-SqliteCsv {
    param(
        [string]$Sqlite3Path,
        [string]$DbPath,
        [string]$SqlScript,
        [string]$WorkDir
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Sqlite3Path
    $psi.Arguments = '"' + $DbPath + '"'
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.WorkingDirectory       = $WorkDir
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.WriteLine($SqlScript)
    $p.StandardInput.Close()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        throw "sqlite3 failed (exit $($p.ExitCode)): $stderr"
    }
}

function To-SqlPath([string]$p) { return ($p -replace '\\','/') }

# Resolve paths
$Sqlite3Path = Get-Sqlite3Path -Override $Sqlite3
$DbPath      = Get-DbPath -Dir $DbDir -File $DbFile
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host "Using sqlite3: $Sqlite3Path"
Write-Host "Using database: $DbPath"
Write-Host "Output directory: $OutDir"

# -------------------------------------------------------
# 1) Direct Export: Full NSRLFile.txt with header
#    Use .headers on and column aliases; no UNION
# -------------------------------------------------------
$nsrlFileOut    = Join-Path $OutDir "NSRLFile.txt"
$nsrlFileOutSql = To-SqlPath $nsrlFileOut

$nsrlFileSql = @"
.mode csv
.headers on
.output "$nsrlFileOutSql"
SELECT
  sha1                                      AS "SHA-1",
  md5                                       AS "MD5",
  crc32                                     AS "CRC32",
  REPLACE(file_name, '"', '')               AS "FileName",
  file_size                                 AS "FileSize",
  package_id                                AS "ProductCode",
  0                                         AS "OpSystemCode",
  ''                                        AS "SpecialCode"
FROM FILE
ORDER BY sha1;
.output stdout
"@

Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $nsrlFileSql -WorkDir (Split-Path $DbPath)

# -------------------------------------------------------
# 2) Direct Export: MD5-only file (one hash per line)
# -------------------------------------------------------
$md5OnlyFile    = Join-Path $OutDir "NSRLFile-MD5-Only.txt"
$md5OnlyFileSql = To-SqlPath $md5OnlyFile

$md5Sql = @"
.mode list
.separator "\n"
.headers off
.output "$md5OnlyFileSql"
SELECT md5
FROM FILE
ORDER BY sha1;
.output stdout
"@

Invoke-SqliteCsv -Sqlite3Path $Sqlite3Path -DbPath $DbPath -SqlScript $md5Sql -WorkDir (Split-Path $DbPath)

Write-Host "✅ NIST NSRL extraction completed." -ForegroundColor green -BackgroundColor black
Write-Host "Full file:    $nsrlFileOut" -ForegroundColor yellow
Write-Host "MD5-only:     $md5OnlyFile" -ForegroundColor yellow
Write-Host "Have a nice day" -ForegroundColor green


