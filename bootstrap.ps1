<#
  bootstrap.ps1 - instalador de uma linha do setup de acesso remoto.
  Universal Windows 10/11. Baixa o setup-remote.ps1 e roda elevado (UAC).

  Uso (PowerShell):
    irm https://tinyurl.com/rdpblox | iex

  Opcoes (defina ANTES do irm, na mesma sessao):
    $env:SSH_PUBKEY = 'ssh-ed25519 AAAA...'  # login SSH sem senha
    $env:TS_AUTHKEY = 'tskey-auth-XXXX'      # entra no Tailscale sem navegador
    $env:TS_TRUST   = 'locked'               # 'locked' (so recebe) ou 'trusted'
    $env:ORDER      = 'vnc,winscp,...'        # quais softwares e em que ordem
    $env:SKIP       = 'volt,wave'            # remove softwares da ordem padrao
    $env:VOLT_URL   = '<url-fresca>'         # volt.exe (presigned expira em 15min)
    $env:CONVERT    = '1'                    # converte Home->Pro (REINICIA)
    $env:NO_APPS    = '1'                    # pula apps/CLIs
    $env:NO_TOOLS   = '1'                    # pula ferramentas de Roblox
    $env:NO_SILENT  = '1'                    # mostra a UI dos instaladores
#>
$ErrorActionPreference = 'Stop'
# TLS moderno: Win10 antigo/PS5.1 usa default fraco e o irm/download falha.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 }
catch { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {} }
$base = 'https://raw.githubusercontent.com/freezerbrastem-blox/rdp-bootstrap/main'
$tmp  = Join-Path $env:TEMP 'setup-remote.ps1'

Write-Host '==> Baixando setup-remote.ps1...' -ForegroundColor Cyan
try {
  Invoke-WebRequest "$base/setup-remote.ps1" -OutFile $tmp -UseBasicParsing -ErrorAction Stop
  if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 100) { throw 'download vazio/curto' }
} catch {
  Write-Host "FALHA ao baixar setup-remote.ps1: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Verifique sua conexao e tente de novo." -ForegroundColor Red
  return
}

$a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$tmp`"")
if ($env:CONVERT)    { $a += '-Convert' }
if ($env:NO_APPS)    { $a += '-NoApps' }
if ($env:NO_TOOLS)   { $a += '-NoTools' }
if ($env:NO_SILENT)  { $a += '-NoSilent' }
if ($env:ORDER)      { $a += @('-Order',     $env:ORDER) }
if ($env:SKIP)       { $a += @('-Skip',      $env:SKIP) }
if ($env:VOLT_URL)   { $a += @('-VoltUrl',   $env:VOLT_URL) }
if ($env:SSH_PUBKEY) { $a += @('-SshPubKey', $env:SSH_PUBKEY) }
if ($env:TS_AUTHKEY) { $a += @('-AuthKey',   $env:TS_AUTHKEY) }
if ($env:TS_TRUST)   { $a += @('-Trust',     $env:TS_TRUST) }

Write-Host '==> Subindo elevado (aceite o UAC)...' -ForegroundColor Cyan
try { Start-Process powershell -Verb RunAs -ArgumentList $a -ErrorAction Stop }
catch {
  Write-Host 'UAC recusado/cancelado. Nada foi instalado. Rode de novo e clique SIM.' -ForegroundColor Red
  return
}
Write-Host '==> Pronto. Acompanhe a janela elevada que abriu.' -ForegroundColor Green
