function _show_help
    echo "
Usage: env_watcher [options] [file...]

Options:
  -h, --help                Show this help message and exit.

Description:
  This script monitors one or more environment files for changes.
  When a change is detected, it will decrypt the monitored file using dotenvx,
  and store the decrypted file in a ramfs memory-based filesystem mount.
  If no file is specified, it defaults to watching '.env.dev'.

  Default path is /mnt/ramfs/dotenvx/*.envfilename*.decrypted
  The subdirectory (by default, named \"dotenvx\") can be changed by specifying the
  environment variable RAMFS_SUBDIR.

Examples:
  1. Watch the default environment file:
     env_watcher

  2. Watch a specific environment file:
     env_watcher .env.dev

  3. Watch multiple environment files:
     env_watcher ~/.env.dev /path/to/.env.prod

  4. Change the subdirectory:
     RAMFS_SUBDIR=projectname; env_watcher

This command allows you to specify custom environment files to monitor. If no arguments are provided,
it assumes the file '.env.dev'. Multiple files can be watched by providing each as an argument separated
by spaces."
end

function _mount_ramfs
    set -l mount_point $argv[1]

    # Create a 20mb ramfs mount if we don't already have one to use
    if not mountpoint -q $mount_point
        sudo mkdir -p $mount_point
        sudo mount -t ramfs -o size=20M,mode=1777 ramfs $mount_point
    end
end

function _watcher_cleanup
    set -l mount_point $argv[1]

    # Cleanup background inotifywatcher jobs
    if test -f /tmp/env_watch_pids.txt
        for p in (cat /tmp/env_watch_pids.txt)
            kill $p 2>/dev/null
        end
        rm /tmp/env_watch_pids.txt 2>/dev/null
    end

    echo ""
    echo "Deleting decrypted env files from memory: $mount_point"
    rm -rf $mount_point > /dev/null
    rm /tmp/env_watch.lock > /dev/null
end

function _decrypt_and_save
    set -l encrypted_file $argv[1]
    set -l mount_point $argv[2]
    set -l decrypted_file $mount_point/(basename $encrypted_file).decrypted

    # Decrypt and convert JSON to .env format
    dotenvx get -f $encrypted_file | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > $decrypted_file
    if test $status -eq 0
        if test (count $argv) -eq 2
            echo "Detected modification in $encrypted_file, decrypting and updating $decrypted_file ..."
        end
    else
        echo "Failed to decrypt $encrypted_file"
        return 1
    end
end

function _run_function_in_background
  fish -c (string join -- ' ' (string escape -- $argv)) &
end

function _setup_watcher
    set -l file $argv[1]
    set -l mount_point $argv[2]

    # Initial run to get the decrypted file into the ramfs mount
    _decrypt_and_save $file $mount_point true

    # Setup watcher to decrypt on modification to env file
    _run_function_in_background inotifywait -q -m -e close_write -e delete_self -e move_self $file | while read -l path action
        set action (string trim "$action")
        echo "Event detected: path=$path, action=$action"
        if test "$action" = "DELETE_SELF" -o "$action" = "MOVE_SELF"
            echo "Env file deleted or moved. Terminating watcher for $file..."
            break
        end
        _decrypt_and_save $file $mount_point
    end

    # Get the decrypted file path and store the PID
    set -l decrypted_file $mount_point/(basename $file).decrypted
    echo "Env file watcher started: $file -> $decrypted_file"
    echo $last_pid >> /tmp/env_watch_pids.txt
end

function _env_watcher_
    set -l sub_dir
    if set -q RAMFS_SUBDIR
        set sub_dir $RAMFS_SUBDIR
    else
        set sub_dir "dotenvx"
    end
    set -l mount_point /mnt/ramfs/$sub_dir

    # Check for another instance running
    if test -f /tmp/env_watch.lock
        echo "Another instance of env:watch is already running. If this is not the case, please check running processes and remove lockfile: /tmp/env_watch.lock"
        return 1
    end

    # Check if inotifywait and jq are installed
    if not command -v inotifywait > /dev/null; or not command -v jq > /dev/null; or not command -v dotenvx > /dev/null
        echo "This script requires inotify-tools, jq, and dotenvx. Please install them first."
        return 1
    end

    # Error if no args supplied to ./run env:watch
    if test (count $argv) -lt 1
        echo "Warning: No env file supplied. Defaulting to .env.dev, see --help for more info."
        set argv ".env.dev"
    end

    for env_file in $argv
        if string match -q "*env.prod*" $env_file; or string match -q "*env.production*" $env_file
            echo "Running on production env files is insecure. The env:watcher should only be used on dev."
            return 1
        end
        if not test -f $env_file
            echo "Error: '$env_file' does not exist."
            return 1
        end
    end

    touch /tmp/env_watch.lock

    # Make sure we don't have a stale pids file
    rm /tmp/env_watch_pids.txt 2>/dev/null

    # Set up ramfs mount and exit cleanup
    _mount_ramfs "/mnt/ramfs"
    function on_exit --on-event fish_exit
        # TODO: does not trap SIGINT yet, cf. https://github.com/fish-shell/fish-shell/issues/6649#issuecomment-1198951287
        _watcher_cleanup /mnt/ramfs/$sub_dir
    end

    # Ensure subdirectory exists
    mkdir -p $mount_point

    # Main loop to setup watchers for each file
    set -l pids
    for env_file in $argv
        _setup_watcher $env_file $mount_point
        set pids $pids $last_pid
    end

    echo "Env file watchers running and waiting for file changes. Ctrl+C to quit..."

    # If all watchers terminate, exit app
    wait $pids
end
