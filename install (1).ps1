# ================================
# Script: Install-DandI.ps1
# Purpose: Automate D&I installation with certificates and MSI sub-installers
# ================================

# Define paths relative to script location
$BasePath   = $PSScriptRoot
$ExePath    = Join-Path $BasePath "D&ISetup420.exe"
$IssPath    = Join-Path $BasePath "install.iss"

$Certs      = @(
    (Join-Path $BasePath "GEMultilin.cer"),
    (Join-Path $BasePath "GeneralElectricCompany.cer")
)
$OthersPath = Join-Path $BasePath "others"

# Logging
$LogDir     = "C:\distrib\logs"
$Stamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$ScriptLog  = Join-Path $LogDir "EnerVista_DandI_420_Install_$Stamp.log"
$LogPath    = Join-Path $LogDir "EnerVista_DandI_420_ISSetup_$Stamp.log"

# -------------------------------
# Function: Write-Log
# -------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t[$Level]`t$Message" | Out-File -FilePath $ScriptLog -Append -Encoding UTF8
    Write-Host "[$Level] $Message"
}

Write-Log "==========================================="
Write-Log "Starting EnerVista D&I Setup 4.20 install."
Write-Log "Running as: $env:USERNAME"
Write-Log "64-bit process: $([Environment]::Is64BitProcess)"
Write-Log "Source files: $BasePath"
Write-Log "==========================================="

# -------------------------------
# Function: Add-Certificate
# -------------------------------
function Add-Certificate {
    param([string]$CertPath)

    if (Test-Path $CertPath) {
        Write-Log "Adding certificate $CertPath to TrustedPublisher store..."
        certutil.exe -addstore -f "TrustedPublisher" $CertPath | Out-Null
        Write-Log "certutil exit code: $LASTEXITCODE"
    } else {
        Write-Log "Certificate not found: $CertPath" -Level 'WARN'
    }
}

# -------------------------------
# Function: Install-MSI
# -------------------------------
function Install-MSI {
    param([string]$MsiPath)

    if (Test-Path $MsiPath) {
        $MsiName = [IO.Path]::GetFileNameWithoutExtension($MsiPath) -replace '\s', ''
        $MsiLog  = Join-Path $LogDir "EnerVista_DandI_420_${MsiName}_$Stamp.log"
        Write-Log "Running MSI installer: $MsiPath"
        Write-Log "MSI log: $MsiLog"
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$MsiPath`" /qn /norestart /L*v `"$MsiLog`"" -Wait -NoNewWindow -PassThru
        Write-Log "msiexec exit code for $MsiName : $($proc.ExitCode)"
    } else {
        Write-Log "MSI file not found: $MsiPath" -Level 'WARN'
    }
}

# -------------------------------
# Step 1: Add Certificates
# -------------------------------
foreach ($cert in $Certs) {
    Add-Certificate -CertPath $cert
}

# -------------------------------
# Step 2: Run Main Installer
# -------------------------------
if ((Test-Path $ExePath) -and (Test-Path $IssPath)) {

    # SYSTEM profile has no Documents/Desktop folders by default - create them
    # so the setup has somewhere to copy per-user files when run under SYSTEM
    $SysProfileDirs = @(
        (Join-Path $env:WINDIR "System32\config\systemprofile\Desktop"),
        (Join-Path $env:WINDIR "System32\config\systemprofile\Documents"),
        (Join-Path $env:WINDIR "SysWOW64\config\systemprofile\Desktop"),
        (Join-Path $env:WINDIR "SysWOW64\config\systemprofile\Documents")
    )
    foreach ($dir in $SysProfileDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Log "Created missing SYSTEM profile folder: $dir"
        }
    }

    # Point TEMP/TMP outside the SYSTEM profile so the 32-bit driver setups
    # don't extract into a redirected SysWOW64 path under SYSTEM context
    $DandITemp = Join-Path $env:WINDIR "Temp\EnerVista_DandI"
    New-Item -Path $DandITemp -ItemType Directory -Force | Out-Null
    $OriginalTemp = $env:TEMP
    $OriginalTmp  = $env:TMP
    $env:TEMP = $DandITemp
    $env:TMP  = $DandITemp
    Write-Log "TEMP and TMP set to $DandITemp (originally $OriginalTemp)"

    Write-Log "Running main installer silently..."
    Write-Log "Arguments: -s -f1`"$IssPath`" -f2`"$LogPath`""
    $proc = Start-Process -FilePath $ExePath -ArgumentList "-s -f1`"$IssPath`" -f2`"$LogPath`"" -Wait -NoNewWindow -PassThru
    Write-Log "Main installer exit code: $($proc.ExitCode)"

    if (Test-Path $LogPath) {
        $ResultLine = Select-String -Path $LogPath -Pattern '^ResultCode=' | Select-Object -First 1
        if ($ResultLine) {
            Write-Log "Main installer $($ResultLine.Line)"
        } else {
            Write-Log "No ResultCode found in $LogPath" -Level 'WARN'
        }
    } else {
        Write-Log "Main installer did not write its log: $LogPath" -Level 'WARN'
    }
    Write-Log "Main installation completed. Log: $LogPath"

    # Restore TEMP/TMP
    $env:TEMP = $OriginalTemp
    $env:TMP  = $OriginalTmp
    Write-Log "TEMP and TMP restored."

} else {
    Write-Log "Main installer or ISS file missing." -Level 'WARN'
}

# -------------------------------
# Step 3: Sequential MSI Installation
# -------------------------------
# Example: explicitly define MSI order
$MsiFiles = @(
    $(Join-Path $OthersPath "1\GE_RNDIS.msi"),
    $(Join-Path $OthersPath "2\GE_RNDIS_400.msi"),
    $(Join-Path $OthersPath "3\GE Bridge RNDIS Driver.msi")
)

foreach ($msi in $MsiFiles) {
    Install-MSI -MsiPath $msi
}

Write-Log "All installations completed."
Write-Log "==========================================="
