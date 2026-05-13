#Requires -Version 5.1
# =============================================================================
# mancomunidad_examenes.ps1
# Preparacion rapida de portatiles para examenes
# - Crea Usuario1 (admin) si no existe
# - Instala LibreOffice via winget
# - Aplica tweaks de rendimiento/limpieza
# - Remueve bloatware
# =============================================================================

# --- Auto-elevar a administrador ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevando permisos de administrador..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# --- Config ---
$NombreUsuario = "Usuario1"
$PasswordUsuario = $null  # Sin password

Clear-Host
Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "    MANCOMUNIDAD - Preparacion para Examenes" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host ""

$pasoActual = 0
$pasoTotal = 4

function Write-Paso {
    param([string]$Titulo)
    $script:pasoActual++
    Write-Host ""
    Write-Host "  [$script:pasoActual/$pasoTotal] $Titulo" -ForegroundColor Cyan
    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
}

# =============================================================================
# PASO 1: Crear usuario (si no existe)
# =============================================================================
Write-Paso "USUARIO: $NombreUsuario"

$usuarioExiste = Get-LocalUser -Name $NombreUsuario -ErrorAction SilentlyContinue

if ($usuarioExiste) {
    Write-Host "  [OK] El usuario '$NombreUsuario' ya existe - omitiendo creacion" -ForegroundColor Green

    # Verificar que sigue siendo admin
    $esAdmin = Get-LocalGroupMember -Group "Administradores" -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like "*\$NombreUsuario" }
    if (-not $esAdmin) {
        # Intentar con nombre en ingles
        $esAdmin = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -like "*\$NombreUsuario" }
    }

    if ($esAdmin) {
        Write-Host "  [OK] Ya es administrador" -ForegroundColor Green
    }
    else {
        Write-Host "  [!!] No es admin, anadiendo al grupo..." -ForegroundColor Yellow
        try {
            Add-LocalGroupMember -Group "Administradores" -Member $NombreUsuario -ErrorAction Stop
            Write-Host "  [OK] Anadido a Administradores" -ForegroundColor Green
        }
        catch {
            try {
                Add-LocalGroupMember -Group "Administrators" -Member $NombreUsuario -ErrorAction Stop
                Write-Host "  [OK] Anadido a Administrators" -ForegroundColor Green
            }
            catch {
                Write-Host "  [!!] No se pudo anadir a admins: $_" -ForegroundColor Red
            }
        }
    }
}
else {
    Write-Host "  Creando usuario '$NombreUsuario'..." -ForegroundColor White

    try {
        net user $NombreUsuario /add /fullname:"$NombreUsuario" /comment:"Cuenta para examenes" /passwordchg:no /active:yes 2>$null | Out-Null
        wmic useraccount where "name='$NombreUsuario'" set PasswordExpires=FALSE 2>$null | Out-Null
        Write-Host "  [OK] Usuario creado (sin password, sin prompt)" -ForegroundColor Green

        net localgroup Administradores $NombreUsuario /add 2>$null
        if ($LASTEXITCODE -ne 0) {
            net localgroup Administrators $NombreUsuario /add 2>$null
        }
        Write-Host "  [OK] Anadido al grupo Administradores" -ForegroundColor Green
    }
    catch {
        Write-Host "  [!!] Error creando usuario: $_" -ForegroundColor Red
    }
}

# =============================================================================
# PASO 2: Tweaks de rendimiento y apariencia (HKLM - aplican a todos)
# =============================================================================
Write-Paso "TWEAKS DEL SISTEMA (todos los usuarios)"

$tweaksHKLM = @(
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Value = 0; Desc = "Desactivar telemetria" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0; Desc = "Desactivar widgets" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"; Name = "EnableFeeds"; Value = 0; Desc = "Desactivar noticias" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowCortana"; Value = 0; Desc = "Desactivar Cortana" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; Value = 0; Desc = "Desactivar Game DVR" }
)

foreach ($tweak in $tweaksHKLM) {
    try {
        if (-not (Test-Path $tweak.Path)) {
            New-Item -Path $tweak.Path -Force | Out-Null
        }
        Set-ItemProperty -Path $tweak.Path -Name $tweak.Name -Value $tweak.Value -Type DWord -Force
        Write-Host "  [OK] $($tweak.Desc)" -ForegroundColor Green
    }
    catch {
        Write-Host "  [!!] $($tweak.Desc): $_" -ForegroundColor Red
    }
}

# Tweaks HKCU (aplican al usuario actual - repetir para cada perfil)
$tweaksHKCU = @(
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"; Name = "EnableTransparency"; Value = 0; Desc = "Desactivar transparencias" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"; Value = 0; Desc = "Ocultar busqueda en taskbar" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowTaskViewButton"; Value = 0; Desc = "Ocultar Task View" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarMn"; Value = 0; Desc = "Ocultar Chat Teams" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAl"; Value = 0; Desc = "Taskbar a la izquierda" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAnimations"; Value = 0; Desc = "Desactivar animaciones taskbar" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideFileExt"; Value = 0; Desc = "Mostrar extensiones" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Hidden"; Value = 1; Desc = "Mostrar archivos ocultos" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "LaunchTo"; Value = 1; Desc = "Explorador en Este equipo" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Value = 0; Desc = "Desactivar ID publicidad" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338388Enabled"; Value = 0; Desc = "Desactivar sugerencias Inicio" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SilentInstalledAppsEnabled"; Value = 0; Desc = "Desactivar apps silenciosas" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338389Enabled"; Value = 0; Desc = "Desactivar notif sugerencias" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; Value = 1; Desc = "Desactivar apps en segundo plano" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BackgroundAppGlobalToggle"; Value = 0; Desc = "Desactivar busqueda background" },
    @{ Path = "Software\Microsoft\GameBar"; Name = "AllowAutoGameMode"; Value = 0; Desc = "Desactivar Game Mode" },
    @{ Path = "Software\Microsoft\GameBar"; Name = "AutoGameModeEnabled"; Value = 0; Desc = "Desactivar auto game mode" },
    @{ Path = "System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 0; Desc = "Desactivar Game DVR usuario" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Value = 0; Desc = "Icono Este equipo en escritorio" },
    @{ Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"; Name = "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}"; Value = 0; Desc = "Icono Red en escritorio" }
)

# Aplicar a TODOS los perfiles de usuario (incluido el Default para nuevos)
Write-Host ""
Write-Host "  Aplicando tweaks a todos los perfiles de usuario..." -ForegroundColor White

# Cargar perfiles existentes desde registry
$profileList = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
    Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
    ForEach-Object {
        $sid = $_.PSChildName
        $profilePath = (Get-ItemProperty $_.PSPath).ProfileImagePath
        @{ SID = $sid; Path = $profilePath; Name = Split-Path $profilePath -Leaf }
    }

# Anadir Default (para futuros usuarios)
$defaultHive = "C:\Users\Default\NTUSER.DAT"

foreach ($profile in $profileList) {
    $hivePath = "HKU:\$($profile.SID)"

    # Montar HKU si no esta disponible
    if (-not (Get-PSDrive HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
    }

    $hiveLoaded = Test-Path $hivePath
    $needUnload = $false

    if (-not $hiveLoaded) {
        $ntuser = Join-Path $profile.Path "NTUSER.DAT"
        if (Test-Path $ntuser) {
            reg load "HKU\$($profile.SID)" $ntuser 2>$null
            $needUnload = $true
            $hiveLoaded = Test-Path $hivePath
        }
    }

    if ($hiveLoaded) {
        Write-Host "  --- Perfil: $($profile.Name) ---" -ForegroundColor DarkCyan
        foreach ($tweak in $tweaksHKCU) {
            try {
                $fullPath = "$hivePath\$($tweak.Path)"
                if (-not (Test-Path $fullPath)) {
                    New-Item -Path $fullPath -Force | Out-Null
                }
                Set-ItemProperty -Path $fullPath -Name $tweak.Name -Value $tweak.Value -Type DWord -Force
            }
            catch { }
        }
        Write-Host "  [OK] $($tweaksHKCU.Count) tweaks aplicados" -ForegroundColor Green
    }

    if ($needUnload) {
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        reg unload "HKU\$($profile.SID)" 2>$null
    }
}

# Aplicar al Default (nuevos usuarios heredan estos tweaks)
if (Test-Path $defaultHive) {
    Write-Host "  --- Perfil: Default (nuevos usuarios) ---" -ForegroundColor DarkCyan
    reg load "HKU\DefaultUser" $defaultHive 2>$null
    if (-not (Get-PSDrive HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
    }

    foreach ($tweak in $tweaksHKCU) {
        try {
            $fullPath = "HKU:\DefaultUser\$($tweak.Path)"
            if (-not (Test-Path $fullPath)) {
                New-Item -Path $fullPath -Force | Out-Null
            }
            Set-ItemProperty -Path $fullPath -Name $tweak.Name -Value $tweak.Value -Type DWord -Force
        }
        catch { }
    }
    Write-Host "  [OK] $($tweaksHKCU.Count) tweaks aplicados al perfil Default" -ForegroundColor Green

    [gc]::Collect()
    Start-Sleep -Milliseconds 500
    reg unload "HKU\DefaultUser" 2>$null
}

# Menu contextual clasico (necesita crear clave especial via reg.exe)
foreach ($profile in $profileList) {
    $sid = $profile.SID
    reg add "HKU\$sid\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /d "" /f 2>$null | Out-Null
}
Write-Host "  [OK] Menu contextual clasico activado" -ForegroundColor Green

# Plan de energia alto rendimiento
Write-Host ""
try {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    powercfg /change monitor-timeout-ac 0
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    Write-Host "  [OK] Plan de energia: Alto rendimiento (sin suspension)" -ForegroundColor Green
}
catch {
    Write-Host "  [!!] Error configurando plan de energia" -ForegroundColor Red
}

# Red privada
try {
    $iface = Get-NetConnectionProfile | Select-Object -First 1 -ExpandProperty InterfaceAlias
    if ($iface) {
        Set-NetConnectionProfile -InterfaceAlias $iface -NetworkCategory Private -ErrorAction SilentlyContinue
        Write-Host "  [OK] Red configurada como privada" -ForegroundColor Green
    }
}
catch { }

# =============================================================================
# PASO 4: Remover bloatware
# =============================================================================
Write-Paso "REMOVER BLOATWARE"

$bloatware = @(
    "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.BingFinance", "Microsoft.BingSports",
    "Microsoft.GetHelp", "Microsoft.Getstarted", "Microsoft.Microsoft3DViewer",
    "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.MixedReality.Portal", "Microsoft.OneConnect", "Microsoft.People",
    "Microsoft.Print3D", "Microsoft.SkypeApp", "Microsoft.WindowsCommunicationsApps",
    "Microsoft.WindowsFeedbackHub", "Microsoft.WindowsMaps",
    "Microsoft.Xbox.TCUI", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay", "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay", "Microsoft.YourPhone",
    "Microsoft.ZuneMusic", "Microsoft.ZuneVideo",
    "Clipchamp.Clipchamp", "Microsoft.Todos", "Microsoft.PowerAutomateDesktop",
    "MicrosoftCorporationII.QuickAssist",
    "king.com.CandyCrushSaga", "king.com.CandyCrushFriends",
    "SpotifyAB.SpotifyMusic", "Disney.37853FC22B2CE",
    "Facebook.Facebook", "Facebook.Instagram", "BytedancePte.Ltd.TikTok",
    "Microsoft.MicrosoftStickyNotes", "MSTeams", "MicrosoftTeams",
    "Microsoft.MicrosoftFamily", "MicrosoftCorporationII.MicrosoftFamily",
    "Google.GooglePlayGames", "DropboxInc.Dropbox", "Dropbox.Dropbox",
    "Microsoft.OutlookForWindows", "Microsoft.549981C3F5F10",
    "MicrosoftWindows.CrossDevice", "MicrosoftWindows.Client.WebExperience"
)

$removidos = 0
$yaNoEstaban = 0

foreach ($app in $bloatware) {
    $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
    if ($pkg) {
        try {
            $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageFullName -ErrorAction SilentlyContinue
            $removidos++
        }
        catch { }
    }
    else {
        $yaNoEstaban++
    }
}

Write-Host "  [OK] Removidos: $removidos | Ya no estaban: $yaNoEstaban" -ForegroundColor Green

# OneDrive
Write-Host "  Desinstalando OneDrive..." -ForegroundColor White
try {
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
        & "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" /uninstall /quiet 2>$null
    }
    elseif (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") {
        & "$env:SystemRoot\System32\OneDriveSetup.exe" /uninstall /quiet 2>$null
    }
    Write-Host "  [OK] OneDrive desinstalado" -ForegroundColor Green
}
catch {
    Write-Host "  [!!] No se pudo desinstalar OneDrive: $_" -ForegroundColor Yellow
}

# =============================================================================
# PASO 5: Resumen
# =============================================================================
Write-Paso "RESUMEN"

Write-Host ""
Write-Host "  Usuario:       $NombreUsuario (admin)" -ForegroundColor White
Write-Host "  Password:      (sin password)" -ForegroundColor White
Write-Host "  Tweaks:        Rendimiento + privacidad + apariencia" -ForegroundColor White
Write-Host "  Bloatware:     Removido" -ForegroundColor White
Write-Host "  Energia:       Alto rendimiento (sin suspension)" -ForegroundColor White
Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "    LISTO - Portatil preparado para examenes" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""

# Reiniciar Explorer para aplicar tweaks visuales
Write-Host "  Reiniciando Explorer para aplicar cambios visuales..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process explorer

Write-Host ""
Write-Host "  Se recomienda reiniciar el equipo para aplicar todos los cambios." -ForegroundColor Yellow
Write-Host ""

$reiniciar = Read-Host "  Reiniciar ahora? (S/N)"
if ($reiniciar -eq "S" -or $reiniciar -eq "s") {
    Write-Host ""
    Write-Host "  Reiniciando en 5 segundos..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}
else {
    Write-Host ""
    Write-Host "  Recuerda reiniciar antes de los examenes." -ForegroundColor Cyan
    Write-Host ""
    Read-Host "  Presiona Enter para cerrar"
}
