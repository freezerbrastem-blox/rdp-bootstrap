<#
  setup-remote.ps1 - Acesso remoto (RDP+SSH+Tailscale) + apps + ferramentas, W10/W11.
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
  [string]$SshPubKey = "", # sua chave PUBLICA -> login SSH sem senha
  [string]$ToolsDir = "$env:USERPROFILE\RobloxTools"
)

$ErrorActionPreference = "Stop"
function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
$Silent = -not $NoSilent
# TLS moderno: Win10 antigo/PS5.1 usa default fraco (TLS1.0) e quebra downloads HTTPS.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 }
catch { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {} }

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
  if ($SshPubKey){ $a += @("-SshPubKey",$SshPubKey) }
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
  if (-not (Have winget)) { Write-Host "  winget ausente - pulei $id" -ForegroundColor Yellow; return }
  if ((winget list --id $id -e --accept-source-agreements --disable-interactivity 2>$null) -match [regex]::Escape($id)) {
    Write-Host "  ja instalado: $id ($desc)"; return
  }
  Write-Host "  instalando: $id ($desc)" -ForegroundColor Yellow
  $sil = if ($Silent) { @('--silent', '--disable-interactivity') } else { @() }
  # winget ja roda o instalador em segundo plano; a maquina continua usavel.
  winget install --id $id -e --source winget --accept-source-agreements --accept-package-agreements @sil
  if ($LASTEXITCODE -eq 3010) { Write-Host "  $id instalado, REBOOT pendente." -ForegroundColor Yellow }
}

# winget instala o Node de forma assincrona; o npm pode demorar a aparecer no PATH.
# Faz polling ate 60s e cobre varios layouts de instalacao.
function Resolve-Npm {
  for ($i = 0; $i -lt 30; $i++) {
    Refresh-Path
    $n = (Get-Command npm -ErrorAction SilentlyContinue).Source
    if (-not $n) {
      foreach ($p in @("$env:ProgramFiles\nodejs\npm.cmd", "${env:ProgramFiles(x86)}\nodejs\npm.cmd", "$env:LOCALAPPDATA\Programs\nodejs\npm.cmd", "$env:APPDATA\npm\npm.cmd")) {
        if (Test-Path $p) { $n = $p; break }
      }
    }
    if ($n -and (Test-Path $n)) { return $n }
    Start-Sleep -Seconds 2
  }
  return $null
}
function Npm-Global($pkg, $desc) {
  $npm = Resolve-Npm
  if ($npm) { Write-Host "  npm i -g $pkg ($desc)" -ForegroundColor Yellow; & $npm install -g $pkg }
  else { Write-Host "  Node/npm nao apareceu em 60s apos winget; pulei $pkg (inclua 'node' antes)." -ForegroundColor Yellow }
}

function Get-Zip($name, $url) {
  New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
  $dest = Join-Path $ToolsDir $name
  if ((Test-Path $dest) -and (Get-ChildItem $dest -Force -ErrorAction SilentlyContinue)) {
    Write-Host "  ja existe: $dest (pulando, nao sobrescreve)"; return
  }
  Write-Host "  baixando $name..." -ForegroundColor Yellow
  $zip = Join-Path $env:TEMP "$name.zip"
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Expand-Archive -Path $zip -DestinationPath $dest -Force
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  Write-Host "  OK: $dest"
}

# ============================ OpenSSH robusto ============================
# Aprendizado: a capability OpenSSH.Server do Windows as vezes fica InstallPending
# e o servico sshd nunca registra (porta 22 fechada). Aqui detectamos isso e caimos
# para o Win32-OpenSSH PORTATIL automaticamente. Tambem habilitamos senha (o default
# as vezes vem PasswordAuthentication=no) e instalamos a chave publica.

function Install-PortableOpenSSH {
  $dest = Join-Path $env:ProgramFiles "OpenSSH"
  $zip  = Join-Path $env:TEMP "OpenSSH-Win64.zip"
  $ex   = Join-Path $env:TEMP "OpenSSH-extract"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Write-Host "  baixando Win32-OpenSSH portatil..." -ForegroundColor Yellow
  Invoke-WebRequest "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip" -OutFile $zip -UseBasicParsing
  if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
  Expand-Archive $zip $ex -Force
  $inner = Get-ChildItem $ex -Directory | Select-Object -First 1
  New-Item -ItemType Directory -Force $dest | Out-Null
  if (Get-Service sshd -ErrorAction SilentlyContinue) { Stop-Service sshd -Force -ErrorAction SilentlyContinue }
  Copy-Item (Join-Path $inner.FullName "*") $dest -Recurse -Force -ErrorAction SilentlyContinue
  Set-ExecutionPolicy Bypass -Scope Process -Force
  & (Join-Path $dest "install-sshd.ps1")
  & (Join-Path $dest "ssh-keygen.exe") -A 2>$null
}

function Enable-SshPassword {
  $cfg = "$env:ProgramData\ssh\sshd_config"
  if (-not (Test-Path $cfg)) { return }
  $c = Get-Content $cfg
  if ($c -match '^\s*#?\s*PasswordAuthentication') {
    $c = $c -replace '^\s*#?\s*PasswordAuthentication\s+\w+', 'PasswordAuthentication yes'
  } else { $c += "PasswordAuthentication yes" }
  Set-Content $cfg $c -Encoding ascii
}

function Install-SshKey($key) {
  $dir = "$env:ProgramData\ssh"; $akf = Join-Path $dir 'administrators_authorized_keys'
  New-Item -ItemType Directory -Force $dir | Out-Null
  $k = $key.Trim()
  $existing = if (Test-Path $akf) { Get-Content $akf -Raw } else { "" }
  if ($existing -notmatch [regex]::Escape($k)) { Add-Content -Path $akf -Value $k -Encoding ascii; Write-Host "  chave adicionada." }
  else { Write-Host "  chave ja instalada." }
  # ACL por SID (independe do idioma): S-1-5-32-544=Administradores, S-1-5-18=SYSTEM.
  # Usar nomes ("Administrators") FALHA em Windows pt-BR e deixa a heranca/Usuarios
  # autenticados, fazendo o sshd IGNORAR a chave (strict mode) -> cai pra senha.
  icacls $akf /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F" | Out-Null
}

function Ensure-SSH {
  Write-Step "Instalando/Configurando OpenSSH Server (porta 22)"
  # 1) tenta a capability nativa
  try { Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null } catch {}
  # 2) capability pendente OU servico nao registrou -> fallback portatil
  $cap = $null
  try { $cap = (Get-WindowsCapability -Online -Name OpenSSH.Server* -ErrorAction SilentlyContinue).State } catch {}
  if ((-not (Get-Service sshd -ErrorAction SilentlyContinue)) -or ($cap -eq 'InstallPending')) {
    Write-Host "  Capability indisponivel/pendente ($cap) -> OpenSSH portatil." -ForegroundColor Yellow
    try { Install-PortableOpenSSH } catch { Write-Host "  falha no portatil: $($_.Exception.Message)" -ForegroundColor Yellow }
  }
  # 3) servico Automatic + start
  Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
  Start-Service sshd -ErrorAction SilentlyContinue
  # 4) habilita senha (gotcha do default 'no') + 5) firewall + 6) chave
  Enable-SshPassword
  if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
  }
  if ($SshPubKey) { Install-SshKey $SshPubKey }
  Restart-Service sshd -ErrorAction SilentlyContinue
  Start-Sleep 2
  $s = Get-Service sshd -ErrorAction SilentlyContinue
  $listen = (Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count
  if ($s -and $s.Status -eq 'Running' -and $listen -gt 0) { Write-Host "OpenSSH OK: porta 22 escutando." -ForegroundColor Green }
  else { Write-Host "OpenSSH NAO subiu (servico=$($s.Status), listen=$listen). Pode exigir reboot da capability." -ForegroundColor Yellow }
}

# ============================ Catalogo de softwares ============================
# Cada item: chave -> @{ Group; Desc; Do = scriptblock }. A ordem padrao e a ordem
# de declaracao aqui. -Order reordena/seleciona; -Skip/-NoApps/-NoTools removem.
# ORDEM PADRAO (escolhida): leves/rapidos -> acesso remoto -> RAM/Volt/Wave -> VS Code -> pesados.
$Catalog = [ordered]@{
  # --- leves/rapidos ---
  vnc        = @{ Group='apps';  Desc='TightVNC';                Do={ Winget-Install 'GlavSoft.TightVNC' 'espelha a tela sem deslogar' } }
  winscp     = @{ Group='apps';  Desc='WinSCP';                  Do={ Winget-Install 'WinSCP.WinSCP' 'transferencia de arquivos' } }
  syncthing  = @{ Group='apps';  Desc='Syncthing';               Do={ Winget-Install 'Syncthing.Syncthing' 'pasta sincronizada' } }
  # --- acesso remoto ---
  mremoteng  = @{ Group='apps';  Desc='mRemoteNG';               Do={ Winget-Install 'mRemoteNG.mRemoteNG' 'multi-conexao em abas' } }
  rustdesk   = @{ Group='apps';  Desc='RustDesk';                Do={ Winget-Install 'RustDesk.RustDesk' 'desktop remoto nao-atendido' } }
  rdm        = @{ Group='apps';  Desc='Remote Desktop Manager';  Do={ Winget-Install 'Devolutions.RemoteDesktopManager' 'grade de sessoes' } }
  ps7        = @{ Group='apps';  Desc='PowerShell 7';            Do={ Winget-Install 'Microsoft.PowerShell' 'Invoke-Command em massa' } }
  # --- ferramentas de Roblox (rapidas) ---
  ram        = @{ Group='tools'; Desc='Roblox Account Manager';  Do={ Get-Zip 'RobloxAccountManager' 'https://github.com/ic3w0lf22/Roblox-Account-Manager/releases/download/3.7.2/Roblox.Account.Manager.3.7.2.zip' } }
  volt       = @{ Group='tools'; Desc='Volt';                    Do={
                   if ($VoltUrl) {
                     New-Item -ItemType Directory -Force (Join-Path $ToolsDir 'Volt') | Out-Null
                     Write-Host "  baixando Volt..." -ForegroundColor Yellow
                     Invoke-WebRequest -Uri $VoltUrl -OutFile (Join-Path $ToolsDir 'Volt\volt.exe') -UseBasicParsing
                     Write-Host "  OK: $ToolsDir\Volt\volt.exe"
                   } else {
                     Write-Host "  Volt: URL expira em 15min. Pegue fresca em https://voltbz.net/ e rode com -VoltUrl '<url>'." -ForegroundColor Yellow
                   } } }
  wave       = @{ Group='tools'; Desc='Wave';                    Do={ Get-Zip 'Wave' 'https://getwave.gg/downloads/Wave.zip' } }
  # --- VS Code ---
  vscode     = @{ Group='dev';   Desc='VS Code';                 Do={ Winget-Install 'Microsoft.VisualStudioCode' 'editor' } }
  # --- pesados por ultimo ---
  node       = @{ Group='dev';   Desc='Node.js (p/ CLIs)';       Do={ Winget-Install 'OpenJS.NodeJS' 'runtime p/ Claude Code/Codex' } }
  claudecode = @{ Group='dev';   Desc='Claude Code CLI';         Do={ Npm-Global '@anthropic-ai/claude-code' 'Claude Code' } }
  codex      = @{ Group='dev';   Desc='Codex CLI';               Do={ Npm-Global '@openai/codex' 'OpenAI Codex' } }
  roblox     = @{ Group='tools'; Desc='Roblox (oficial)';        Do={
                   if (Have winget) {
                     Winget-Install 'Roblox.Roblox' 'cliente oficial'
                   } else {
                     New-Item -ItemType Directory -Force $ToolsDir | Out-Null
                     Invoke-WebRequest 'https://www.roblox.com/download/client' -OutFile (Join-Path $ToolsDir 'RobloxPlayerLauncher.exe') -UseBasicParsing
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
try { Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0 -ErrorAction Stop }
catch { Write-Host "  RDP fDenyTSConnections falhou: $($_.Exception.Message)" -ForegroundColor Yellow }
$rdpTcp = "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
try {
  if (Test-Path $rdpTcp) { Set-ItemProperty $rdpTcp -Name UserAuthentication -Value 1 -ErrorAction Stop }
  else { Write-Host "  RDP-Tcp ainda nao existe (Home/feature off) - pulando NLA." -ForegroundColor Yellow }
} catch { Write-Host "  NLA falhou: $($_.Exception.Message)" -ForegroundColor Yellow }

Write-Step "Abrindo regra de firewall do RDP"
Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28752" -ErrorAction SilentlyContinue

Write-Step "Garantindo a conta em 'Remote Desktop Users'"
$me = "$env:USERDOMAIN\$env:USERNAME"
try { Add-LocalGroupMember -SID S-1-5-32-555 -Member $me -ErrorAction Stop; Write-Host "Adicionado: $me" }
catch { Write-Host "Ja era membro (ou e admin): $me" }

Ensure-SSH
if (-not $SshPubKey) {
  Write-Host "Sem -SshPubKey: SSH por senha (habilitada). Passe sua chave publica para login sem senha." -ForegroundColor Yellow
}

# ============================ Softwares (ordem escolhida) =====================
$seq = Resolve-Sequence
if ($seq) {
  Write-Step "Instalando softwares nesta ordem: $($seq -join ' -> ')"
  # Defender costuma apagar executores -> excluir a pasta de tools (estamos elevados)
  if ($seq | Where-Object { $Catalog[$_].Group -eq 'tools' }) {
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    try { Add-MpPreference -ExclusionPath $ToolsDir -ErrorAction Stop; Write-Host "Defender: '$ToolsDir' excluida da verificacao." }
    catch { Write-Host "(nao consegui excluir do Defender - pode apagar executores)" -ForegroundColor Yellow }
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
  # Trust: so pergunta se houver console interativo E nao houver authkey; senao default seguro 'locked'.
  if (-not $Trust) {
    if ($AuthKey -or -not [Environment]::UserInteractive) {
      $Trust = "locked"
      Write-Host "TS_TRUST nao informado -> assumindo 'locked' (so recebe)." -ForegroundColor Yellow
    } else {
      Write-Host ""
      Write-Host "Este dispositivo deve poder INICIAR conexoes com seus outros aparelhos?" -ForegroundColor Yellow
      Write-Host "  [S] Sim -> confiavel    [N] Nao -> SO RECEBE conexao (recomendado)"
      $resp = Read-Host "Permitir que ele inicie conexoes? (S/N)"
      $Trust = if ($resp -match '^[Ss]') { "trusted" } else { "locked" }
    }
  }
  $tagArgs = @()
  if ($Trust -eq "locked") { $tagArgs = @("--advertise-tags=$LockTag"); Write-Host "Modo BLOQUEADO: $LockTag." -ForegroundColor Green }
  else { Write-Host "Modo CONFIAVEL." -ForegroundColor Green }
  $upArgs = @("--accept-routes", "--unattended")   # --unattended: tunel sobrevive a logoff (VPS)
  if ($AuthKey) { $upArgs += @("--authkey", $AuthKey) }
  else { Write-Host "AVISO: sem AuthKey o Tailscale abre login no navegador e NAO conclui sozinho. Gere em https://login.tailscale.com/admin/settings/keys" -ForegroundColor Yellow }
  try {
    $out = & $ts up @upArgs @tagArgs 2>&1; $out | Out-Host
    if ($LASTEXITCODE -ne 0 -and ($out -match 'tag')) {
      Write-Host "Tag nao autorizada na ACL -> subindo SEM tag (configure tagOwners no admin depois)." -ForegroundColor Yellow
      & $ts up @upArgs
    }
    Write-Host "IP Tailscale:" -ForegroundColor Green
    & $ts ip -4
  } catch { Write-Host "  Tailscale falhou ($($_.Exception.Message)). Rode 'tailscale up' manualmente depois." -ForegroundColor Yellow }
} else { Write-Host "  Tailscale nao instalado (winget pode ter falhado)." -ForegroundColor Yellow }

# ============================ Conversao Home->Pro (UNICO reboot) ==============
if ($isHome -and $Convert) {
  Write-Step "Convertendo Home -> Pro (UNICO passo que reinicia)"
  Write-Host "ATENCAO: o changepk abre uma JANELA que pede confirmacao e reinicia." -ForegroundColor Yellow
  Write-Host "Salve seu trabalho. Se a janela nao aparecer, clique nela na barra de tarefas." -ForegroundColor Yellow
  try { Start-Process "$env:WINDIR\System32\changepk.exe" -ArgumentList "/ProductKey", $ProKey -Wait }
  catch { Write-Host "  changepk falhou: $($_.Exception.Message). Converta manual em Configuracoes > Ativacao." -ForegroundColor Yellow }
  return
}

Write-Step "Pronto. A maquina continua usavel. Conecte via mstsc/ssh + Tailscale."
