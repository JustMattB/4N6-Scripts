############## EXTRACT THE NIST NSRL INFOR FROM THE NIST DB AND CREATE A MD5 LIST FOR USE WITH DF TOOLS ##############
############## Requires PowerShell and SQLITE3.exe from sqlite.org ##############

[CmdletBinding()]
param(
    # THE PATH WHERE THE DB IS
    [Parameter(Mandatory=$false)]
    [string]$DbDir  = "D:\RDS_2025.03.1_android",

    # THE DB NAME
    [Parameter(Mandatory=$false)]
    [string]$DbFile = "RDS_2025.03.1_android.db",  # If blank, the newest *.db in DbDir is used.

    # YOUR OUTPUT DIR
    [Parameter(Mandatory=$false)]
    [string]$OutDir = "D:\NSRL_Output",

    # PATH TO THE SQLITE3 APPLICATION
    [Parameter(Mandatory=$false)]
    [string]$Sqlite3 = "D:\sqlite-tools-win-x64-3500400\sqlite3.exe"
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

