<img src="logo.png" alt="Miniamp" width="96" align="right">

# Miniamp

A local PHP stack for macOS that installs **without admin rights**: PHP, MariaDB and phpMyAdmin from Homebrew,
started at login, managed from a native control panel (or the `miniamp` command line tool). If you know MAMP, it
works much the same way.

| What | Where |
|---|---|
| Your sites | http://localhost:8888 (files in `~/Sites/localhost`) |
| phpMyAdmin | http://localhost:8888/phpMyAdmin/ (logs in automatically) |
| Database | MariaDB on `127.0.0.1:3306`, user `root` / password `root` |

Everything listens on `127.0.0.1` only, so the `root`/`root` defaults are not reachable from the network.

![Miniamp: the Servers and Setup tabs](docs/screenshot.png)

## Requirements

- Apple Silicon Mac, macOS 14 or later
- [Homebrew](https://brew.sh) in `/opt/homebrew`, owned by your user. Installing Homebrew needs an admin once;
  after that, `brew install` works without one.

## Install

### With Homebrew (recommended)

```bash
brew install dnovitski/tap/miniamp
```

Then open the control panel with `miniamp open` and click **Install** on the **Setup** tab, or run `miniamp install`.
This also puts a copy of Miniamp in `~/Applications`, so you can start it from Spotlight and Launchpad.

Homebrew builds the app on your Mac, so macOS does not block it the way it blocks downloaded apps.

To update, run `brew upgrade miniamp`, then click **Repair** (or run `miniamp install`) to refresh the copy in
`~/Applications`.

### Manual download

1. Download `Miniamp-<version>.zip` from the [latest release](https://github.com/dnovitski/miniamp/releases/latest).
2. Unzip it and move **Miniamp.app** to `~/Applications`.
3. The app is not notarized, so macOS blocks the downloaded copy. Remove the quarantine flag once, which needs no admin
   rights:

   ```bash
   xattr -dr com.apple.quarantine ~/Applications/Miniamp.app
   ```

   With admin rights you can instead open it once and click **Open Anyway** under System Settings → Privacy &
   Security.
4. Open Miniamp, click **Install** on the **Setup** tab and follow the log.

If you switch from a manual download to Homebrew, run `brew link --overwrite miniamp` so Homebrew takes over the
`miniamp` command.

## Control panel

**Servers** shows the web server and MariaDB with their status, starts and stops them (individually or all at once),
toggles *Start at login*, and opens the website, phpMyAdmin, the document root and the logs.

**Setup** shows a checklist of what is installed and configured:

| Button | What it does |
|---|---|
| Install / Repair | Runs every step that is not done yet: Homebrew packages, MariaDB on 127.0.0.1 with root/root, phpMyAdmin auto-login, web server, `miniamp` command, and for Homebrew installs the copy in `~/Applications`. Then it turns on *Start at login* and starts both servers. Safe to repeat. |
| Update Packages | `brew upgrade php mariadb phpmyadmin`, restarts what was running, then repairs the setup if needed |
| Uninstall… | Stops the servers and removes the Miniamp configuration, optionally also the Homebrew packages. Sites and databases are always kept. |

Progress streams into the log while it runs. Earlier runs are in `~/Library/Logs/miniamp/setup.log`.

The app also lives in the menu bar. Quitting the app does not stop the servers. To show the menu bar icon after
login, add the app under System Settings → General → Login Items.

## Command line

Install links `miniamp` into `/opt/homebrew/bin`. It is the same program as the app:

```
miniamp status                       Show the servers and the setup state
miniamp start|stop|restart [web|db]  Control both servers, or one
miniamp autostart on|off             Start the servers at login
miniamp install                      Install or repair the setup
miniamp update                       Upgrade PHP, MariaDB and phpMyAdmin
miniamp uninstall [--packages]       Remove the setup (sites and databases are kept)
miniamp open                         Open the control panel
```

## How it works

Both servers are launchd LaunchAgents in your own login session, so no root is involved:

| Server | Label | Runs |
|---|---|---|
| Web server | `local.miniamp.web` | `php -S 127.0.0.1:8888` with a small router for `/phpMyAdmin` |
| MariaDB | `sh.brew.mariadb` | Homebrew's own plist, so it stays in sync with `brew services` |

- **Start:** `launchctl bootstrap`, then `kickstart`.
- **Stop:** `launchctl bootout`, then wait until the job is gone. MariaDB needs a few seconds to shut down, and
  restarting before that fails.
- **Start at login:** the plist is present in `~/Library/LaunchAgents`.

| File | Purpose |
|---|---|
| `Sources/Core.swift` | Paths, launchd control, running processes with live output |
| `Sources/Setup.swift` | Install, update and uninstall steps, and the generated config files |
| `Sources/CLI.swift` | The `miniamp` command |
| `Sources/App.swift`, `Sources/Views.swift` | The SwiftUI control panel and menu bar |
| `Sources/main.swift` | Starts the CLI when called with a command, else the app |
| `tools/icon.swift` | Renders the app icon and `logo.png` |
| `docs/screenshot.png` | The screenshot above |
| `build.sh` | Builds `build/Miniamp.app` (`--install` copies it to `~/Applications`) |

## Building and releasing

Building needs Xcode or the Command Line Tools:

```bash
./build.sh --install
```

GitHub Actions builds every push on a macOS runner. Pushing a tag `v1.2.3` publishes a release with
`Miniamp-1.2.3.zip`, and updates the formula in [dnovitski/homebrew-tap](https://github.com/dnovitski/homebrew-tap)
if the repository has a `TAP_TOKEN` secret (a token that can push to the tap).

## Trademarks

MAMP is a trademark of appsolute GmbH. Miniamp is an independent project and is not affiliated with or endorsed by
appsolute. Mac and macOS are trademarks of Apple Inc.
