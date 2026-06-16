<#
  bootstrap.ps1 — instalador de uma linha do setup de acesso remoto.
  Universal Windows 10/11. Baixa o setup-remote.ps1 e roda elevado (UAC).

  Uso minimo (interativo — ele pergunta confiavel/bloqueado):
    irm https://raw.githubusercontent.com/freezerbrastem-blox/rdp-bootstrap/main/bootstrap.ps1 | iex

  Opcoes (defina ANTES do irm, na mesma sessao):
    $env:TS_AUTHKEY = 'tskey-auth-XXXX'   # entra no Tailscale sem navegador
    $env:TS_TRUST   = 'locked'            # 'locked' (so recebe) ou 'trusted'
    $env:CONVERT    = '1'                 # converte Home->Pro (REINICIA)
    $env:NO_APPS    = '1'                 # nao instala os apps (so RDP/SSH/Tailscale)
#>
$ErrorActionPreference = 'Stop'
$base = 'https://raw.githubusercontent.com/freezerbrastem-blox/rdp-bootstrap/main'
$tmp  = Join-Path $env:TEMP 'setup-remote.ps1'

Write-Host '==> Baixando setup-remote.ps1...' -ForegroundColor Cyan
Invoke-RestMethod "$base/setup-remote.ps1" -OutFile $tmp

$a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$tmp`"")
if ($env:CONVERT)    { $a += '-Convert' }
if ($env:NO_APPS)    { $a += '-NoApps' }
if ($env:TS_AUTHKEY) { $a += @('-AuthKey', $env:TS_AUTHKEY) }
if ($env:TS_TRUST)   { $a += @('-Trust',   $env:TS_TRUST) }

Write-Host '==> Subindo elevado (aceite o UAC)...' -ForegroundColor Cyan
Start-Process powershell -Verb RunAs -ArgumentList $a
Write-Host '==> Pronto. Acompanhe a janela elevada que abriu.' -ForegroundColor Green
