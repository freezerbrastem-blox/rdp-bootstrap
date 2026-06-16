<#
  setup-remote.ps1 — Configura acesso remoto nativo (RDP) + Tailscale.
  Universal Windows 10 / 11. Auto-eleva (UAC). Idempotente.

  Etapas:
    1. (Home) Converte a edicao para Pro via changepk (chave generica MS) -> habilita RDP host
    2. Habilita Remote Desktop (fDenyTSConnections=0) + NLA
    3. Abre a regra de firewall do RDP
    4. Garante que a conta atual esta em "Remote Desktop Users"
    5. Sobe o Tailscale e mostra a URL de login (passo interativo)

  Uso:
    powershell -ExecutionPolicy Bypass -File setup-remote.ps1            # tudo, menos a conversao
    powershell -ExecutionPolicy Bypass -File setup-remote.ps1 -Convert   # inclui conversao Home->Pro (REINICIA)
#>
param(
  [switch]$Convert,
  [string]$ProKey = "VK7JG-NPHTM-C97JM-9MPGT-3V66T",  # chave GENERICA Pro (so troca edicao; nao ativa)
  [string]$AuthKey = "",   # tskey-auth-... -> sobe o Tailscale SEM login no navegador
  [ValidateSet("","trusted","locked")]
  [string]$Trust = "",     # trusted = pode iniciar conexoes; locked = so RECEBE (tag:untrusted). Vazio = pergunta.
  [string]$LockTag = "tag:untrusted",
  [switch]$NoApps          # pula a instalacao dos apps de acesso remoto
)

# Apps de acesso remoto/arquivos (id winget, descricao). Idempotente; W10/W11.
$Apps = @(
  @{ Id = "mRemoteNG.mRemoteNG";                Desc = "gerenciador multi-conexao RDP/SSH/VNC em abas" }
  @{ Id = "Devolutions.RemoteDesktopManager";   Desc = "painel com grade de sessoes remotas" }
  @{ Id = "WinSCP.WinSCP";                      Desc = "transferencia de arquivos SFTP/SCP arrasta-e-solta" }
  @{ Id = "Syncthing.Syncthing";                Desc = "pasta sincronizada entre todas as maquinas" }
  @{ Id = "RustDesk.RustDesk";                  Desc = "desktop remoto nao-atendido (nao desloga o farm)" }
  @{ Id = "GlavSoft.TightVNC";                  Desc = "servidor/visualizador VNC (mantem a GUI viva)" }
  @{ Id = "Microsoft.PowerShell";               Desc = "PowerShell 7 (Invoke-Command em massa)" }
)

$ErrorActionPreference = "Stop"

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

# ---- Auto-elevacao ----
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
  Write-Step "Solicitando elevacao (UAC)..."
  $argsList = @("-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
  if ($Convert) { $argsList += "-Convert" }
  if ($AuthKey) { $argsList += @("-AuthKey",$AuthKey) }
  if ($Trust)   { $argsList += @("-Trust",$Trust) }
  if ($NoApps)  { $argsList += "-NoApps" }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $argsList
  return
}

Write-Step "Edicao atual"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host $os.Caption
$isHome = $os.Caption -match "Home"
if ($isHome -and -not $Convert) {
  Write-Host "AVISO: edicao Home nao hospeda RDP. Rode com -Convert para converter para Pro." -ForegroundColor Yellow
}

# ---- 1b. Git (instala se faltar) ----
Write-Step "Verificando Git"
if (Get-Command git -ErrorAction SilentlyContinue) {
  Write-Host "Git ja instalado: $(git --version)"
} else {
  Write-Host "Git nao encontrado. Instalando via winget..." -ForegroundColor Yellow
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
  } else {
    Write-Host "winget indisponivel. Baixe Git em https://git-scm.com/download/win" -ForegroundColor Yellow
  }
}

# ---- 2. Habilitar Remote Desktop + NLA ----
Write-Step "Habilitando Remote Desktop + NLA"
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1

# ---- 3. Firewall ----
Write-Step "Abrindo regra de firewall do RDP"
Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28752" -ErrorAction SilentlyContinue

# ---- 4. Remote Desktop Users ----
Write-Step "Garantindo a conta em 'Remote Desktop Users'"
$me = "$env:USERDOMAIN\$env:USERNAME"
try { Add-LocalGroupMember -SID S-1-5-32-555 -Member $me -ErrorAction Stop; Write-Host "Adicionado: $me" }
catch { Write-Host "Ja era membro (ou e admin): $me" }

# ---- 4b. OpenSSH Server ----
Write-Step "Instalando/Configurando OpenSSH Server (porta 22)"
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service sshd -ErrorAction SilentlyContinue
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}
Write-Host "OpenSSH Server ativo na porta 22."

# ---- 4c. Apps de acesso remoto (winget, idempotente) ----
if (-not $NoApps) {
  Write-Step "Instalando apps (mRemoteNG, RDM, WinSCP, Syncthing, RustDesk, VNC, PS7)"
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    foreach ($app in $Apps) {
      $installed = (winget list --id $app.Id -e) -match [regex]::Escape($app.Id)
      if ($installed) {
        Write-Host "  ja instalado: $($app.Id) ($($app.Desc))"
      } else {
        Write-Host "  instalando: $($app.Id) ($($app.Desc))" -ForegroundColor Yellow
        winget install --id $app.Id -e --source winget --accept-source-agreements --accept-package-agreements
      }
    }
    Write-Host "Nota: Chrome Remote Desktop nao vem no winget — instale pelo navegador se usar."
  } else {
    Write-Host "winget indisponivel — pulando apps. Instale o 'App Installer' pela Microsoft Store." -ForegroundColor Yellow
  }
} else {
  Write-Host "(-NoApps: pulando instalacao de apps)"
}

# ---- 5. Tailscale ----
$ts = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $ts)) {
  Write-Step "Instalando Tailscale (winget)"
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id Tailscale.Tailscale -e --source winget --accept-source-agreements --accept-package-agreements
  } else {
    Write-Host "winget indisponivel. Baixe: https://tailscale.com/download/windows" -ForegroundColor Yellow
  }
}
Write-Step "Subindo Tailscale"
if (Test-Path $ts) {
  # Pergunta (se nao veio por parametro): este dispositivo pode INICIAR conexoes?
  if (-not $Trust) {
    Write-Host ""
    Write-Host "Este dispositivo deve poder INICIAR conexoes com seus outros aparelhos?" -ForegroundColor Yellow
    Write-Host "  [S] Sim  -> confiavel (acesso normal na rede)"
    Write-Host "  [N] Nao  -> bloqueado: SO RECEBE conexao (recomendado p/ PC que nao e seu)"
    $resp = Read-Host "Permitir que ele inicie conexoes? (S/N)"
    $Trust = if ($resp -match '^[Ss]') { "trusted" } else { "locked" }
  }

  $tagArgs = @()
  if ($Trust -eq "locked") {
    $tagArgs = @("--advertise-tags=$LockTag")
    Write-Host "Modo BLOQUEADO: aplicando $LockTag (so recebe conexao)." -ForegroundColor Green
  } else {
    Write-Host "Modo CONFIAVEL: acesso normal." -ForegroundColor Green
  }

  if ($AuthKey) {
    & $ts up --accept-routes --authkey $AuthKey @tagArgs   # sem navegador
  } else {
    & $ts up --accept-routes @tagArgs                      # login interativo (URL)
  }
  Write-Host "IP Tailscale:" -ForegroundColor Green
  & $ts ip -4
} else {
  Write-Host "Tailscale nao instalado. Baixe em https://tailscale.com/download/windows" -ForegroundColor Yellow
}

# ---- 6. Conversao Home -> Pro (POR ULTIMO: reinicia) ----
if ($isHome -and $Convert) {
  Write-Step "Convertendo Home -> Pro (vai REINICIAR ao final)"
  Start-Process "$env:WINDIR\System32\changepk.exe" -ArgumentList "/ProductKey",$ProKey -Wait
  Write-Host "Conversao disparada. Apos reiniciar, o RDP ja estara habilitado (Pro)." -ForegroundColor Yellow
  return
}

Write-Step "Pronto. Conecte via mstsc usando o IP/hostname Tailscale acima."
