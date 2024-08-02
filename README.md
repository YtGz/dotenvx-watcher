# dotenvx-watcher

Env file watcher that watches and decrypts env files on the fly, using Dotenvx for decryption, and stores them in a file-system accessible path for easy loading into a Docker `env_file` directive, so that your Docker containers can be fed live env var file changes.

## Prerequisites

fish, [dotenvx](https://github.com/dotenvx/dotenvx), inotify-tools, jq.

```shell
# Install dependencies
paru inotify-tools jq curl
curl -sfS https://dotenvx.sh | sudo sh
git clone https://github.com/YtGz/dotenvx-watcher.git
cd dotenvx-watcher
cp env_watcher.fish ~/.config/fish/functions/env_watcher.fish
mkdir ~/.config/fish/lib && cp env_watcher_helpers.fish ~/.config/fish/lib/env_watcher_helpers.fish
source ~/.config/fish/config.fish
```

## Usage

```shell
# Start the watcher from project root containing your .env files
env_watcher
```

This env file watcher was primarily created to assist with the integration of Dotenvx into projects that are heavily Docker based.

After trying to integrate Dotenvx with Docker the "traditional" way, I decided that this was a much nicer solution. You can read more about this process in an article I wrote here: [https://dev.to/nullbio/dotenvx-with-docker-the-better-way-to-do-environment-variable-management-5c0n](https://dev.to/nullbio/dotenvx-with-docker-the-better-way-to-do-environment-variable-management-5c0n).

### Example usage

```
Usage: env_watcher [options] [file...]

Options:
  -h, --help                Show this help message and exit.

Description:
  This script monitors one or more environment files for changes.
  When a change is detected, it will decrypt the monitored file using dotenvx,
  and store the decrypted file in a ramfs memory-based filesystem mount.
  If no file is specified, it defaults to watching '.env.dev'.

  Default path is /mnt/ramfs/dotenvx/*.envfilename*.decrypted
  The subdirectory (by default, named "dotenvx") can be changed by specifying the
  environment variable RAMFS_SUBDIR.

Examples:
  1. Watch the default environment file:
     env_watcher

  2. Watch a specific environment file:
     env_watcher .env.dev

  3. Watch multiple environment files:
     env_watcher ~/.env.dev /path/to/.env.prod

  4. Change the subdirectory where the decrypted files are stored:
     set -x RAMFS_SUBDIR projectname
     env_watcher
```

```yaml
# compose.yml
services:
  postgres:
    image: postgres:latest
    env_file:
      - /mnt/ramfs/dotenvx/.env.dev.decrypted
    environment:
      # $POSTGRES_PASSWORD is decrypted inside .env.dev.decrypted
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD
```

Regular usage example:

```
$: env_watcher
Env file watcher started: .env.dev -> /mnt/ramfs/dotenvx/.env.dev.decrypted
Env file watchers running and waiting for file changes. Ctrl+C to quit...
Detected modification in .env.dev, decrypting and updating /mnt/ramfs/dotenvx/.env.dev.decrypted ...
^C
Deleting decrypted env files from memory: /mnt/ramfs/dotenvx
```

Specify custom subdirectory:

```console
$: set -x RAMFS_SUBDIR projectname
$: env_watcher
Env file watcher started: .env.dev -> /mnt/ramfs/projectname/.env.dev.decrypted
```
