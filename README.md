# SocialAgent — install kit

Your AI social-media agent, running privately on your own PC. This kit
installs everything.

## Install (Windows)

1. **Download this kit**: [ZIP download](https://github.com/Gamergy/socialagent-releases/archive/refs/heads/main.zip)
   and unzip it into a folder (anywhere is fine — the installer copies the app
   to its own home).
2. **Double-click `Install SocialAgent.cmd`** and approve the admin prompt.
3. Answer the one question:
   - **Local AI models** — free and private, ~8 GB download, best on a PC
     with a gaming GPU; or
   - **Cloud API key** — you paste a Claude (Anthropic) or OpenAI key in the
     app instead; no big download, ideal for laptops. (You can add the local
     models later from the app — Settings → Local AI models.)

The installer takes care of Docker Desktop, Chrome, the browser helper,
shortcuts, and the first start. **If it installs Docker for the first time it
will ask you to restart the PC — just run the installer again afterwards; it
continues where it left off.** While the images are private, it also asks for
your access token.

When it finishes, a **SocialAgent** icon is on your desktop — the app lives at
http://localhost:5174 in your browser.

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
