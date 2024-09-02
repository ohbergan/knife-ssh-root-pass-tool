# Server Password Updater Tool

This tool allows you to update root passwords on multiple servers using Chef's knife tool. It supports search queries for selecting servers and verifies that the password was changed successfully. To use this tool, you need SSH access and sudo privileges on the target servers.

## Prerequisites

Before using this tool, ensure the following commands are installed and available on your system:

- `openssl`: Used for password hashing.
- `sshpass`: Required for non-interactive ssh password authentication.
- `knife`: Essential for interacting with Chef servers.

You can check if these are installed by running `command -v <command-name>` for each command (replace `<command-name>` with `openssl`, `sshpass`, or `knife`). If any of these commands are not installed, you will need to install them before proceeding.

## Installation

Download the tool [here](http://example.com/download-tool).

## Usage

### Display Help

To display help and see all available options, run:

```bash
./update-root-pass.sh --help
```

### Options

- `-p` Specify the password in clear text (will be hashed unless you specify the hash). This will be used to verify that the changed password will work.
- `-h` Specify the hash to use.
- `-o` Specify an output file to save the results.
- `-l` List the machines without changing passwords.
- `--hosts` Specify a list of hosts separated by space.
- `--help` Display this help message.

## Examples

- Generate a sha-512 hash, this is what the tool would generate as well:
  ```bash
  $ openssl passwd -6
  Password:
  Verifying - Password:
  $6$5q...
  ```
- List all CentOS machines without changing passwords and save the results to a file:
  ```bash
  ./update-root-pass.sh -l -o results.txt 'platform:centos'
  ```
- Change the password on all hosts specified in the list:
  ```bash
  ./update-root-pass.sh -p 'myPassword123' --hosts 'fqdn1 fqdn2'
  ```
- Change the password on all nodes in the Chef server matching the search query:
  ```bash
  ./update-root-pass.sh -p 'myPassword123' 'name:*'
  ```
- Change the password on all nodes in the Chef server matching the search query using the specified password hash:
  ```bash
  ./update-root-pass.sh -p 'myPassword123' -h '$6$saltsalt$hashedpasswordhere' 'name:*'
  ```
