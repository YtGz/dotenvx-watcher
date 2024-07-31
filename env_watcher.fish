function env_watcher
    # Source helper functions
    source ~/.config/fish/lib/env_watcher_helpers.fish

    switch $argv[1]
        case -h --help
        _show_help
        case '*'
            # Call the internal _env_watcher_ function here
            _env_watcher_ $argv
    end
end