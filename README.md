# SocialAgent — install & update kit

This repo is the **client starter kit** for SocialAgent: everything a machine
needs to run the app. The app itself ships as three pre-built Docker images;
this kit is the small set of files that runs them together. **No source code
and no secrets live here or in the images.**

`latest.json` in this repo announces the newest published version — installed
copies check it to show their "update available" prompt.

## Requirements

- Windows 10/11 (or Linux/macOS), 16 GB RAM recommended
- **Docker Desktop** installed and running (its whale icon says "Engine running").
  On Windows, Docker Desktop needs WSL 2 — if it complains, run `wsl --update`
  in an **administrator** PowerShell and reboot.

## Install

1. **Download this kit**: [ZIP download](https://github.com/Gamergy/socialagent-releases/archive/refs/heads/main.zip)
   — unzip it into a folder you'll keep, e.g. `C:\SocialAgent`. Everything below
   happens inside that folder.
2. **Rename `.env.client.example` to `.env`** (keep it in the same folder).
   The defaults are already correct; nothing needs editing.
3. **Log in to the image registry** (only needed while the images are private):

   ```
   docker login ghcr.io -u Gamergy
   ```

   Password = the access token you were given (not a GitHub password).
4. **Start it:**

   ```
   docker compose -f docker-compose.client.yml up -d
   ```

   The **first** start downloads the AI models (~8 GB) — let it work; later
   starts are fast.
5. Open **http://localhost:5174** and finish onboarding. Your own keys and
   account logins are entered in the app and stored **encrypted on this
   machine only** — never inside the images.
   Social-media login windows appear at **http://localhost:7900/vnc.html**.

## Updating (and undo)

- **Windows:** double-click **`Update SocialAgent.cmd`**. It finds the newest
  published version and switches to it. Changed your mind or something broke?
  Double-click **`Rollback SocialAgent.cmd`** to return to the version you were
  on before.
- **Linux/macOS:** `./update.sh latest` — and `./update.sh rollback` to undo.

Your accounts, memory, and settings **survive updates and rollbacks** — they
live in Docker volumes on your machine, not in the app images.

## Troubleshooting

- `docker compose -f docker-compose.client.yml ps` — shows what's running.
- `docker compose -f docker-compose.client.yml logs browser-worker` — the main
  app log; share this if you're reporting a problem.
- Stop everything: `docker compose -f docker-compose.client.yml down`
  (your data stays; `up -d` brings it back).
