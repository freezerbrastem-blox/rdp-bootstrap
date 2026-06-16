# rdp-bootstrap

Instalador de **uma linha** para acesso remoto em Windows 10/11:
RDP + OpenSSH + Tailscale + apps (mRemoteNG, Remote Desktop Manager, WinSCP,
Syncthing, RustDesk, TightVNC, PowerShell 7). Idempotente, auto-eleva (UAC).

## Uso (PowerShell)

Mínimo (pergunta confiável/bloqueado no meio):
```powershell
irm https://raw.githubusercontent.com/freezerbrastem-blox/rdp-bootstrap/main/bootstrap.ps1 | iex
```

Autônomo (sem navegador, travado como "só recebe"):
```powershell
$env:TS_AUTHKEY='tskey-auth-XXXX'; $env:TS_TRUST='locked'
irm https://raw.githubusercontent.com/freezerbrastem-blox/rdp-bootstrap/main/bootstrap.ps1 | iex
```

Incluindo conversão Home→Pro (REINICIA):
```powershell
$env:CONVERT='1'; $env:TS_AUTHKEY='tskey-auth-XXXX'; $env:TS_TRUST='locked'
irm https://raw.githubusercontent.com/freezerbrastem-blox/rdp-bootstrap/main/bootstrap.ps1 | iex
```

### Variáveis de ambiente (opcionais, antes do `irm`)
| Var | Efeito |
|---|---|
| `TS_AUTHKEY` | entra no Tailscale sem login no navegador |
| `TS_TRUST` | `locked` (só recebe) ou `trusted` |
| `CONVERT` | `1` = converte Home→Pro (reinicia) |
| `NO_APPS` | `1` = não instala os apps (só RDP/SSH/Tailscale) |

## O que faz
Git → habilita RDP (+NLA, firewall, conta) → instala/liga OpenSSH (porta 22) →
instala os apps → instala Tailscale e entra na rede. Tudo gratuito.

> A versão em **Rust** equivalente (binário único, com testes e `--dry-run`) fica
> no projeto principal (`RDP_PC_bootstrap`).
