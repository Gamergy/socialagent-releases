# SocialAgent — install kit

Your AI social-media agent, running privately on your own PC. This kit
installs everything.

## Install (Windows)

1. **Download the installer**: [**SocialAgent-Setup.exe**](https://github.com/Gamergy/socialagent-releases/releases/latest/download/SocialAgent-Setup.exe)
   (one file).
2. **Double-click it** and approve the Windows permission prompt.
3. Click through the wizard. On the one question that matters, pick:
   - **Local AI models** — free and private, ~8 GB download, best on a PC
     with a gaming GPU; or
   - **Cloud API key** — you paste a Claude (Anthropic) or OpenAI key in the
     app instead; no big download, ideal for laptops. (You can add the local
     models later from the app — Settings → Local AI models.)
4. Paste your access token when asked (only needed while the app is private),
   then finish.

The installer takes care of Docker Desktop, Chrome, the browser helper,
shortcuts, and the first start.

> **First time with Docker on this PC?** The installer may need to install
> Docker and ask you to **restart Windows**. After the restart, just run
> **SocialAgent-Setup.exe** again — it picks up where it left off.

When it finishes, a **SocialAgent** icon is on your desktop — the app lives at
http://localhost:5174 in your browser. To remove it later: **Windows Settings →
Apps → SocialAgent → Uninstall**.

<details><summary>Prefer the manual, no-installer route?</summary>

Download the [ZIP kit](https://github.com/Gamergy/socialagent-releases/archive/refs/heads/main.zip),
unzip anywhere, and double-click `Install SocialAgent.cmd`. Same result — the
Setup.exe is just a friendlier wrapper around these same files.
</details>

## How logins work (worth knowing)

When you connect Instagram/X/LinkedIn/TikTok, the agent opens **your own
Chrome** in a normal window — you log in like a person, close the window, and
the agent keeps that session for posting and DMs. Nothing about your logins
ever leaves this PC; they're stored in a separate Chrome profile per account.

## Updating (and undo)

- **`Update SocialAgent.cmd`** (desktop shortcut) — finds the newest published
  version and switches to it. Your accounts, memory, and settings survive.
- **`Rollback SocialAgent.cmd`** — instantly return to the version you were on
  before the last update.

## Uninstalling

Double-click **`Uninstall SocialAgent.cmd`** (or the desktop shortcut), type
YES, and everything is removed: the app, all downloaded AI models, the agent's
memory, and saved logins. Docker Desktop and Chrome stay (they're
general-purpose programs).

## Troubleshooting

From the install folder (`C:\SocialAgent`) in PowerShell:

- `docker compose -f docker-compose.client.yml ps` — what's running
- `docker compose -f docker-compose.client.yml logs browser-worker` — main app
  log; include this when reporting a problem
- App won't answer right after a local-models install? The ~8 GB model
  download is still running — check
  `docker compose -f docker-compose.client.yml logs ollama`
