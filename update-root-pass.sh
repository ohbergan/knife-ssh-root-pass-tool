#!/bin/bash

# ANSI color codes
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
BOLD="\033[1m"
RESET="\033[0m"

# Initialize variables
PASSWORD=""
PASSWORD_HASH=""
OUTPUT_FILE=""
LIST_ONLY=0
MODE="search" # Default mode is search
HOSTS_INPUT=""
INVALID_OPTION=0

# Function to display help
function display_help() {
  echo -e "${BOLD}Usage:${RESET} ${BLUE}$0 [options] [--hosts 'host1 host2'] <search-query>${RESET}\n"
  echo -e "${BOLD}Description:${RESET} Lets you update the root passwords on multiple servers using Chef's knife tool. Search queries supported. Verifies that the password was changed. You need SSH access and sudo privileges on the servers.\n"
  echo -e "${BOLD}Options:${RESET}"
  echo -e "  ${BLUE}-p${RESET}       Specify the password in clear text (will be hashed)."
  echo -e "  ${BLUE}-h${RESET}       Specify an existing password hash to use."
  echo -e "  ${BLUE}-o${RESET}       Specify an output file to save the results."
  echo -e "  ${BLUE}-l${RESET}       List the machines without changing passwords."
  echo -e "  ${BLUE}--hosts${RESET}  Specify a list of hosts separated by space."
  echo -e "  ${BLUE}--help${RESET}   Display this help message.\n"
  echo -e "${BOLD}Example:${RESET}"
  echo -e "  ${BLUE}$0 -l -o results.txt 'platform:centos'${RESET} - List all CentOS machines without changing passwords and save the results to a file."
  echo -e "  ${BLUE}$0 -p 'myPassword123' --hosts 'host1 host2'${RESET} - Changes password on all hosts specified in the list."
  echo -e "  ${BLUE}$0 -p 'myPassword123' 'name:*'${RESET} - Changes password on all nodes in the Chef server matching the search query."
  echo -e "  ${BLUE}$0 -p 'myPassword123' -h '\$6\$saltsalt\$hashedpasswordhere' 'name:*'${RESET} - Changes password on all nodes in the Chef server matching the search query using the specified password hash."
}

check_dependencies() {
    # Initialize an error flag
    local error=0

    # Check for knife
    if ! command -v knife &> /dev/null; then
        echo "knife is required but it's not installed. Please install it." >&2
        error=1
    fi

    # Check for sshpass
    if ! command -v sshpass &> /dev/null; then
        echo "sshpass is required but it's not installed. Please install it." >&2
        error=1
    fi

    # Check for openssl
    if ! command -v openssl &> /dev/null; then
        echo "openssl is required but it's not installed. Please install it." >&2
        error=1
    fi

    # Return the error flag
    return $error
}

if ! check_dependencies; then
  echo "Some dependencies are missing. Please install them before proceeding." >&2
  exit 1
fi

# Parse options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -p) PASSWORD="$2"; shift ;;
    -h) PASSWORD_HASH="$2"; shift ;;
    -o) OUTPUT_FILE="$2"; shift ;;
    -l) LIST_ONLY=1 ;;
    --hosts) HOSTS_INPUT="$2"; MODE="list"; shift ;;
    --help) display_help; exit 0 ;;
    *) 
      if [[ -n $1 && $1 != -* ]]; then
        SEARCH_QUERY="$1"
      else
        echo -e "${RED}${BOLD}Invalid option:${RESET}${RED} $1${RESET}" >&2
        INVALID_OPTION=1
      fi ;;
  esac
  shift
done

# Check for invalid option
if [[ $INVALID_OPTION -eq 1 ]]; then
  echo -e "\nUse ${BLUE}$0 --help${RESET} to display usage information."
  exit 1
fi

# Check for required password or hash unless listing only
if { [ -z "$PASSWORD" ] && [ "$LIST_ONLY" -ne 1 ]; } || { [ -n "$PASSWORD_HASH" ] && [ -z "$PASSWORD" ]; }; then
  echo -e "${RED}${BOLD}Error:${RESET}${RED} A password is required.${RESET}\n" >&2
  echo -e "Use ${BLUE}$0 --help${RESET} to display usage information."
  exit 1
fi

# If a clear text password is provided, and there is no hash, create a hash
if [ -n "$PASSWORD" ] && [ -z "$PASSWORD_HASH" ]; then
  PASSWORD_HASH=$(openssl passwd -6 "$PASSWORD")
  echo -e "${GREEN}Generated password hash:${RESET} $PASSWORD_HASH\n"
fi

# Encode PASSWORD_HASH to base64 (or it will most likely mess things up)
ENCODED_CHPASSWD_IN=$(echo -n "root:$PASSWORD_HASH" | base64 -w0)

main() {
  # Use knife to get a list of nodes based on the search query
  if [ "$MODE" = "search" ]; then
    HOSTS=$(knife search node "$SEARCH_QUERY" -a name -F json | jq -r '.rows[] | to_entries[] | .key')
  else
    HOSTS=$HOSTS_INPUT
  fi

  # Initialize result arrays
  SUCCESSFUL_HOSTS=()
  FAILED_HOSTS=()

  # Clear the output file if it exists
  if [ -n "$OUTPUT_FILE" ]; then
    > "$OUTPUT_FILE"
  fi

  if [ "$LIST_ONLY" -eq 1 ]; then
    echo "Performing actions on the following nodes:"
  fi

  # Perform actions on nodes
  for host in $HOSTS; do
    if [ "$LIST_ONLY" -eq 1 ]; then
      if [ -n "$OUTPUT_FILE" ]; then
        echo "- $host" | tee -a "$OUTPUT_FILE"
      else
        echo "- $host"
      fi
    else
      echo "- Updating password for root on $host"

      # Update the password using knife ssh
      knife ssh "name:$host" "echo $ENCODED_CHPASSWD_IN | base64 --decode | sudo /usr/sbin/chpasswd -e" -y
      echo "  - Sent new password"
      echo "  - Verifying password change"
      
      # Verify the password change by attempting to SSH into the server using sshpass
      if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -o PreferredAuthentications=password root@$host 'exit'; then
        echo "  - Success"
        SUCCESSFUL_HOSTS+=("$host")
      else
        echo "  - Failed"
        FAILED_HOSTS+=("$host")
      fi
    fi
  done

  # Print the results  
  if [ "$LIST_ONLY" -ne 1 ]; then
    if [ -n "${SUCCESSFUL_HOSTS[*]}" ]; then
      echo
      echo -e "${GREEN}${BOLD}Successful Hosts:${RESET}"
      if [ -n "$OUTPUT_FILE" ]; then
        echo -e "Successful Hosts:" >> "$OUTPUT_FILE"
        printf '%s\n' "${SUCCESSFUL_HOSTS[@]}" | tee -a "$OUTPUT_FILE"
      else
        printf '%s\n' "${SUCCESSFUL_HOSTS[@]}"
      fi
    fi

    if [ -n "$OUTPUT_FILE" ]; then
      echo -e "" >> "$OUTPUT_FILE"
    fi

    if [ -n "${FAILED_HOSTS[*]}" ]; then
      echo
      echo -e "${RED}${BOLD}Failed Hosts:${RESET}"
      if [ -n "$OUTPUT_FILE" ]; then
        printf 'Failed Hosts:\n' | tee -a "$OUTPUT_FILE"
        printf '%s\n' "${FAILED_HOSTS[@]}" | tee -a "$OUTPUT_FILE"
      else
        printf '%s\n' "${FAILED_HOSTS[@]}"
      fi
    fi
  fi
}

# Execute the function
main
