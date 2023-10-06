#!/bin/bash

# Boolean that identifies a "dry_run" where no fetch and pull commands are executed
dry=false

# Defining terminal colors
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'

# Array to store git repositories and their update status
declare -a REPORT_LIST

# checks if given directory is a git repository and executes fetch & pull if so
function sync_dir {
    local dir="$1"

    # Check if the directory is in the ignore list
    if grep -Fxq "$dir" "$HOME/.gitsync_ignore"; then
        echo -e "Directory ${CYAN}\`${GREEN}$dir${CYAN}\` is in the GitSync ignore list. Skipping.${RESET}"
        return 0
    fi

    # If contains a .git directory inside, it's a git repository
    if [ -d "$dir/.git" ]; then
        echo -e "Depth ${BLUE}$depth${RESET}: ${CYAN}Updating git repository at \`${GREEN}$dir${BLUE}\`...${RESET}"
        cd "$dir" || exit

        if [ "$dry" = true ]; then
            echo -e "${PURPLE} - Dry run${RESET}: Skipping actual fetch and pull for repository ${GREEN}\`$dir\`${RESET}"
            REPORT_LIST+=("${YELLOW}\`$dir\`${RESET}: Is a git repository")
        else

            # Execute fetch and pull
            git fetch --all
            pull_output=$(git pull 2>&1 | tee /dev/tty) # Capture the output of git pull

            # Match output
            case "$pull_output" in

                # Contains "Fast-forward" as a substring = repo updated
                *Fast-forward*)
                    REPORT_LIST+=("${GREEN}\`$dir\`${RESET}: Updated")
                    ;;

                # Otherwise = not updated
                *)
                    REPORT_LIST+=("${YELLOW}\`$dir\`${RESET}: Not Updated")
                    ;;
            esac

            # cd out of dir and restore default output
            cd - > /dev/null 2>&1 || exit
        fi

        return 0
    fi
    return 1
}


# Checks recursivelly for each directory inside directory $1 (base_dir) until $3 (depth) reaches $2 (max_depth)
function check_for_git_repos {
    local base_dir="$1"
    local max_depth="$2"
    local depth="$3"

    # For each dir in base_dir
    for dir in $(find "$base_dir" -maxdepth 1 -mindepth 1 -type d); do

        # Call sync_dir to try syncing the directory
        sync_dir "$dir"

        # If sync_dir returns 1, directory is not a git repo
        if [ $? -eq 1 ]; then

            # Max_depth not reached yet, check subdirectories of $dir
            if [ "$depth" -lt "$max_depth" ]; then
                echo -e "Depth ${BLUE}$depth${RESET}: \`${RED}$dir${RESET}\` ${YELLOW}is not a git repository, checking subdirectories.${RESET}"
                check_for_git_repos "$dir" "$max_depth" "$((depth + 1))"

            # Max_depth reached, exit
            else
                echo -e "Depth ${BLUE}$depth${RESET}: \`${RED}$dir${RESET}\` ${PURPLE}is not a git repository.${RESET}"
            fi
        fi
    done
}

# Function to add a directory to the ignore list
function add_to_ignore_list {
    local dir="$1"
    echo "$dir" >> "$HOME/.gitsync_ignore"
    echo "Added \`$dir\` to the GitSync ignore list."
}

# Function to remove a directory from the ignore list
function remove_from_ignore_list {
    local dir="$1"
    if grep -qFx "$dir" "$HOME/.gitsync_ignore"; then
        sed -i "/^$dir$/d" "$HOME/.gitsync_ignore"
        echo "Removed \`$dir\` from the GitSync ignore list."
    else
        echo "\`$dir\` is not in the GitSync ignore list."
    fi
}

# Function to display the current ignore list
function display_ignore_list {
    echo "GitSync Ignore List:"
    cat "$HOME/.gitsync_ignore"
}


# Parse options using getopts
while getopts "d" opt; do
    case "$opt" in
        d)
            dry=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            # usage
            ;;
    esac
done

shift $((OPTIND - 1))


depth_default=3

# Main script logic
case "$1" in
    "install")
        cp "$0" "$HOME/.local/bin/gitsync"
        chmod +x "$HOME/.local/bin/gitsync"
        echo "GitSync installed successfully"
        ;;
    "ignore")
        shift

        if [ -z "$1" ]; then
            echo "Usage: gitsync ignore [DIRECTORY | ls | rm DIRECTORY]"
            exit 1
        fi

        case "$1" in
            "rm")
                shift
                if [ -z "$1" ]; then
                    echo "Usage: gitsync ignore remove DIRECTORY"
                else
                    remove_from_ignore_list "$1"
                fi
                ;;
            "ls")
                display_ignore_list
                ;;
            *)
                add_to_ignore_list "$1"
                ;;
        esac
        ;;
    *)
        # Target directory to run the script. Is either the first argument or defaults to the current directory
        target_dir="${1:-.}"

        # Maximim depth to search for repositories in subdirectories. Is either the second argument or defaults to 2
        max_depth="${2:-${depth_default}}"
        if [[ -z "$max_depth" || ! "$max_depth" =~ ^[0-9]+$ ]]; then
            max_depth=$depth_default
            echo -e "Using default value of ${BLUE}\`$max_depth\`${RESET} for max_depth"
        fi

        # Logging
        echo -e "Syncing all repositories inside \`${BLUE}$target_dir${RESET}\` with maximum depth of ${CYAN}$max_depth${RESET}."

        # Start recursion
        check_for_git_repos "$target_dir" "$max_depth" 1
        # Print the list of Git repositories and their update status
        echo -e "\n${BLUE}Report:${RESET}"
        for item in "${REPORT_LIST[@]}"; do
            echo -e "$item"
        done
        ;;
esac
