# rdp-bootstrap

Instalador de **uma linha** para Windows 10/11. Configura acesso remoto e
instala seu kit de ferramentas. Idempotente, auto-eleva (UAC), instala em
**silencioso** (a máquina continua usável) e **não reinicia** (exceto `CONVERT`).

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

Escolhendo a **ordem/quais** softwares instalar:
```powershell
$env:ORDER='vscode,node,claudecode,codex'   # só esses, nessa ordem
irm https://raw.githubusercontent.com/freezerbrastem-blox/rdp-bootstrap/main/bootstrap.ps1 | iex
```

Com Volt (a URL expira em ~15min — pegue fresca em https://voltbz.net/):
```powershell
$env:VOLT_URL='<url-fresca-do-volt>'
irm https://raw.githubusercontent.com/freezerbrastem-blox/rdp-bootstrap/main/bootstrap.ps1 | iex
```

### Variáveis de ambiente (antes do `irm`)
| Var | Efeito |
|---|---|
| `ORDER` | lista por vírgula: **quais** softwares e em **que ordem** |
| `SKIP` | lista por vírgula: remove softwares da ordem padrão |
| `TS_AUTHKEY` | entra no Tailscale sem login no navegador |
| `TS_TRUST` | `locked` (só recebe) ou `trusted` |
| `VOLT_URL` | URL fresca do `volt.exe` (presigned, expira em ~15min) |
| `CONVERT` | `1` = converte Home→Pro (**único** passo que reinicia) |
| `NO_APPS` | `1` = pula apps/CLIs |
| `NO_TOOLS` | `1` = pula ferramentas de Roblox |
| `NO_SILENT` | `1` = mostra a UI dos instaladores |

### Chaves do `ORDER`/`SKIP` (ordem padrão)
`vscode, node, claudecode, codex, mremoteng, rdm, winscp, syncthing, rustdesk, vnc, ps7, roblox, ram, wave, volt`

## O que configura (infra, sempre)
RDP (+NLA, firewall, conta em "Remote Desktop Users") · OpenSSH Server (porta 22) ·
Git · Tailscale (instala e entra na rede, pergunta confiável/bloqueado).

## O que instala (softwares, ordenáveis)
| Chave | App | Pra quê |
|---|---|---|
| `vscode` | VS Code | editor |
| `node` | Node.js | runtime p/ as CLIs abaixo |
| `claudecode` | Claude Code | CLI (via npm) |
| `codex` | Codex | CLI (via npm) |
| `mremoteng` | mRemoteNG | várias VPS em abas |
| `rdm` | Remote Desktop Manager | grade de sessões |
| `winscp` | WinSCP | arquivos (arrasta e solta) |
| `syncthing` | Syncthing | arquivos em TODAS as máquinas |
| `rustdesk` | RustDesk | desktop remoto sem deslogar o farm |
| `vnc` | TightVNC | espelha tela sem deslogar |
| `ps7` | PowerShell 7 | comando em massa |
| `roblox` | Roblox oficial | cliente |
| `ram` | Roblox Account Manager | multi-conta |
| `wave` | Wave | executor |
| `volt` | Volt | executor (precisa de `VOLT_URL`) |

> A versão em **Rust** (binário único, 20 testes, `--dry-run`) fica no projeto
> principal (`RDP_PC_bootstrap`). Ferramentas de Roblox são para automação dos
> seus próprios farms.
