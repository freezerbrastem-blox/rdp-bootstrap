<#
  setup-remote.ps1 â€” Acesso remoto (RDP+SSH+Tailscale) + apps + ferramentas, W10/W11.
  Auto-eleva (UAC). Idempotente. Instalacoes SILENCIOSAS (a maquina continua usavel).
  NAO reinicia, exceto se voce passar -Convert (conversao Home->Pro).

  Voce ESCOLHE a ordem/quais softwares instalar com -Order (lista por virgula).
  Chaves disponiveis (ordem padrao):
    vscode, node, claudecode, codex,
    mremoteng, rdm, winscp, syncthing, rustdesk, vnc, ps7,
    roblox, ram, wave, volt

  Exemplos:
    setup-remote.ps1                                   # tudo, ordem padrao
    setup-remote.ps1 -Order "vscode,node,claudecode"   # so esses, nessa ordem
    setup-remote.ps1 -Skip "volt,wave"                 # tudo menos esses
    setup-remote.ps1 -Convert -AuthKey tskey-... -Trust locked
#>
param(
  [switch]$Convert,
  [string]$ProKey  = "VK7JG-NPHTM-C97JM-9MPGT-3V66T",
  [string]$AuthKey = "",
  [ValidateSet("","trusted","locked")]
  [string]$Trust   = "",
  [string]$LockTag = "tag:untrusted",
  [string]$Order   = "",   # lista por virgula: define QUAIS e em QUE ORDEM
  [string]$Skip    = "",   # lista por virgula: remove da ordem padrao
  [switch]$NoApps,         # atalho: pula o grupo de apps de acesso remoto
  [switch]$NoTools,        # atalho: pula o grupo de ferramentas de Roblox
  [switch]$NoSilent,       # mostra a UI dos instaladores (padrao = silencioso)
  [string]$VoltUrl = "",   # URL FRESCA do volt.exe (presigned expira em ~15min)
  [string]$ToolsDir = "$env:USERPROFILE\RobloxTools"
)

$ErrorActionPreference = "Stop"
function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
$Silent = -not $NoSilent

# ---- Auto-elevacao (passa todos os parametros adiante) ----
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
  Write-Step "Solicitando elevacao (UAC)..."
  $a = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
  if ($Convert)  { $a += "-Convert" }
  if ($AuthKey)  { $a += @("-AuthKey",$AuthKey) }
  if ($Trust)    { $a += @("-Trust",$Trust) }
  if ($Order)    { $a += @("-Order",$Order) }
  if ($Skip)     { $a += @("-Skip",$Skip) }
  if ($NoApps)   { $a += "-NoApps" }
  if ($NoTools)  { $a += "-NoTools" }
  if ($NoSilent) { $a += "-NoSilent" }
  if ($VoltUrl)  { $a += @("-VoltUrl",$VoltUrl) }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $a
  return
}

# ============================ Helpers de instalacao ============================
function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path','User')
}

function Winget-Install($id, $desc) {
  if (-not (Have winget)) { Write-Host "  winget ausente â€” pulei $id" -ForegroundColor Yellow; return }
  if ((winget list --id $id -e 2>$null) -match [regex]::Escape($id)) {
    Write-Host "  ja instalado: $id ($desc)"; return
  }
  Write-Host "  instalando: $id ($desc)" -ForegroundColor Yellow
  $sil = if ($Silent) { @('--silent') } else { @() }
  # winget ja roda o instalador em segundo plano; a maquina continua usavel.
  winget install --id $id -e --source winget --accept-source-agreements --accept-package-agreements @sil
}

function Npm-Global($pkg, $desc) {
  Refresh-Path
  $npm = (Get-Command npm -ErrorAction SilentlyContinue).Source
  if (-not $npm) { $npm = "C:\Program Files\nodejs\npm.cmd" }
  if (Test-Path $npm) {
    Write-Host "  npm i -g $pkg ($desc)" -ForegroundColor Yellow
    & $npm install -g $pkg
  } else {
    Write-Host "  Node/npm ausente â€” inclua 'node' ANTES de '$pkg' no -Order." -ForegroundColor Yellow
  }
}

function Get-Zip($name, $url) {
  New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
  $dest = Join-Path $ToolsDir $name
  Write-Host "  baixando $name..." -ForegroundColor Yellow
  $zip = Join-Path $env:TEMP "$name.zip"
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Expand-Archive -Path $zip -DestinationPath $dest -Force
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  Write-Host "  OK: $dest"
}

# ============================ Catalogo de softwares ============================
# Cada item: chave -> @{ Group; Desc; Do = scriptblock }. A ordem padrao e a ordem
# de declaracao aqui. -Order reordena/seleciona; -Skip/-NoApps/-NoTools removem.
$Catalog = [ordered]@{
  vscode     = @{ Group='dev';   Desc='VS Code';                 Do={ Winget-Install 'Microsoft.VisualStudioCode' 'editor' } }
  node       = @{ Group='dev';   Desc='Node.js (p/ CLIs)';       Do={ Winget-Install 'OpenJS.NodeJS' 'runtime p/ Claude Code/Codex' } }
  claudecode = @{ Group='dev';   Desc='Claude Code CLI';         Do={ Npm-Global '@anthropic-ai/claude-code' 'Claude Code' } }
  codex      = @{ Group='dev';   Desc='Codex CLI';               Do={ Npm-Global '@openai/codex' 'OpenAI Codex' } }
  mremoteng  = @{ Group='apps';  Desc='mRemoteNG';               Do={ Winget-Install 'mRemoteNG.mRemoteNG' 'multi-conexao em abas' } }
  rdm        = @{ Group='apps';  Desc='Remote Desktop Manager';  Do={ Winget-Install 'Devolutions.RemoteDesktopManager' 'grade de sessoes' } }
  winscp     = @{ Group='apps';  Desc='WinSCP';                  Do={ Winget-Install 'WinSCP.WinSCP' 'transferencia de arquivos' } }
  syncthing  = @{ Group='apps';  Desc='Syncthing';               Do={ Winget-Install 'Syncthing.Syncthing' 'pasta sincronizada' } }
  rustdesk   = @{ Group='apps';  Desc='RustDesk';                Do={ Winget-Install 'RustDesk.RustDesk' 'desktop remoto nao-atendido' } }
  vnc        = @{ Group='apps';  Desc='TightVNC';                Do={ Winget-Install 'GlavSoft.TightVNC' 'espelha a tela sem deslogar' } }
  ps7        = @{ Group='apps';  Desc='PowerShell 7';            Do={ Winget-Install 'Microsoft.PowerShell' 'Invoke-Command em massa' } }
  roblox     = @{ Group='tools'; Desc='Roblox (oficial)';        Do={
                   if (Have winget) {
                     Winget-Install 'Roblox.Roblox' 'cliente oficial'
                   } else {
                     New-Item -ItemType Directory -Force $ToolsDir | Out-Null
                     Invoke-WebRequest 'https://www.roblox.com/download/client' -OutFile (Join-Path $ToolsDir 'RobloxPlayerLauncher.exe') -UseBasicParsing
                   } } }
  ram        = @{ Group='tools'; Desc='Roblox Account Manager';  Do={ Get-Zip 'RobloxAccountManager' 'https://github.com/ic3w0lf22/Roblox-Account-Manager/releases/download/3.7.2/Roblox.Account.Manager.3.7.2.zip' } }
  wave       = @{ Group='tools'; Desc='Wave';                    Do={ Get-Zip 'Wave' 'https://getwave.gg/downloads/Wave.zip' } }
  volt       = @{ Group='tools'; Desc='Volt';                    Do={
                   if ($VoltUrl) {
                     New-Item -ItemType Directory -Force (Join-Path $ToolsDir 'Volt') | Out-Null
                     Write-Host "  baixando Volt..." -ForegroundColor Yellow
                     Invoke-WebRequest -Uri $VoltUrl -OutFile (Join-Path $ToolsDir 'Volt\volt.exe') -UseBasicParsing
                     Write-Host "  OK: $ToolsDir\Volt\volt.exe"
                   } else {
                     Write-Host "  Volt: URL expira em 15min. Pegue fresca em https://voltbz.net/ e rode com -VoltUrl '<url>'." -ForegroundColor Yellow
                   } } }
}

# Monta a sequencia final a partir de -Order / -Skip / -NoApps / -NoTools
function Resolve-Sequence {
  $skip = @()
  if ($Skip)    { $skip += ($Skip -split '[,; ]+' | Where-Object { $_ }) }
  if ($NoApps)  { $skip += ($Catalog.Keys | Where-Object { $Catalog[$_].Group -eq 'apps' }) }
  if ($NoTools) { $skip += ($Catalog.Keys | Where-Object { $Catalog[$_].Group -eq 'tools' }) }

  if ($Order) {
    $seq = $Order -split '[,; ]+' | Where-Object { $_ }
    $bad = $seq | Where-Object { -not $Catalog.Contains($_) }
    if ($bad) { Write-Host "Chaves desconhecidas em -Order: $($bad -join ', ')" -ForegroundColor Yellow }
    return $seq | Where-Object { $Catalog.Contains($_) -and $skip -notcontains $_ }
  }
  return $Catalog.Keys | Where-Object { $skip -notcontains $_ }
}

# ============================ Infra de acesso remoto ============================
Write-Step "Edicao atual"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host $os.Caption
$isHome = $os.Caption -match "Home"
if ($isHome -and -not $Convert) {
  Write-Host "AVISO: edicao Home nao hospeda RDP. Rode com -Convert para converter para Pro." -ForegroundColor Yellow
}

Write-Step "Verificando Git"
if (Have git) { Write-Host "Git ja instalado: $(git --version)" }
else { Winget-Install 'Git.Git' 'controle de versao' }

Write-Step "Habilitando Remote Desktop + NLA"
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1

Write-Step "Abrindo regra de firewall do RDP"
Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28752" -ErrorAction SilentlyContinue

Write-Step "Garantindo a conta em 'Remote Desktop Users'"
$me = "$env:USERDOMAIN\$env:USERNAME"
try { Add-LocalGroupMember -SID S-1-5-32-555 -Member $me -ErrorAction Stop; Write-Host "Adicionado: $me" }
catch { Write-Host "Ja era membro (ou e admin): $me" }

Write-Step "Instalando/Configurando OpenSSH Server (porta 22)"
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service sshd -ErrorAction SilentlyContinue
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}
Write-Host "OpenSSH Server ativo na porta 22."

# ============================ Softwares (ordem escolhida) =====================
$seq = Resolve-Sequence
if ($seq) {
  Write-Step "Instalando softwares nesta ordem: $($seq -join ' -> ')"
  # Defender costuma apagar executores -> excluir a pasta de tools (estamos elevados)
  if ($seq | Where-Object { $Catalog[$_].Group -eq 'tools' }) {
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    try { Add-MpPreference -ExclusionPath $ToolsDir -ErrorAction Stop; Write-Host "Defender: '$ToolsDir' excluida da verificacao." }
    catch { Write-Host "(nao consegui excluir do Defender â€” pode apagar executores)" -ForegroundColor Yellow }
  }
  foreach ($key in $seq) {
    Write-Host "`n- $key ($($Catalog[$key].Desc))" -ForegroundColor White
    try { & $Catalog[$key].Do }
    catch { Write-Host "  falhou ${key}: $($_.Exception.Message)" -ForegroundColor Yellow }
  }
} else {
  Write-Host "`n(nenhum software selecionado)"
}

# ============================ Tailscale ======================================
$ts = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $ts)) {
  Write-Step "Instalando Tailscale"
  Winget-Install 'Tailscale.Tailscale' 'rede mesh'
}
Write-Step "Subindo Tailscale"
if (Test-Path $ts) {
  if (-not $Trust) {
    Write-Host ""
    Write-Host "Este dispositivo deve poder INICIAR conexoes com seus outros aparelhos?" -ForegroundColor Yellow
    Write-Host "  [S] Sim -> confiavel    [N] Nao -> SO RECEBE conexao (recomendado)"
    $resp = Read-Host "Permitir que ele inicie conexoes? (S/N)"
    $Trust = if ($resp -match '^[Ss]') { "trusted" } else { "locked" }
  }
  $tagArgs = @()
  if ($Trust -eq "locked") { $tagArgs = @("--advertise-tags=$LockTag"); Write-Host "Modo BLOQUEADO: $LockTag." -ForegroundColor Green }
  else { Write-Host "Modo CONFIAVEL." -ForegroundColor Green }
  if ($AuthKey) { & $ts up --accept-routes --authkey $AuthKey @tagArgs }
  else          { & $ts up --accept-routes @tagArgs }
  Write-Host "IP Tailscale:" -ForegroundColor Green
  & $ts ip -4
}

# ============================ Conversao Home->Pro (UNICO reboot) ==============
if ($isHome -and $Convert) {
  Write-Step "Convertendo Home -> Pro (este e o UNICO passo que reinicia)"
  Write-Host "Salve seu trabalho â€” o Windows vai reiniciar ao terminar." -ForegroundColor Yellow
  Start-Process "$env:WINDIR\System32\changepk.exe" -ArgumentList "/ProductKey",$ProKey
  return
}

Write-Step "Pronto. A maquina continua usavel. Conecte via mstsc/ssh + Tailscale."
