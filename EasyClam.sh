#!/bin/bash

# ASCII banner
cat << "EOF"
#    ______                 _____ _
#   |  ____|               / ____| |
#   | |__   __ _ ___ _   _| |    | | __ _ _ __ ___
#   |  __| / _` / __| | | | |    | |/ _` | '_ ` _ \
#   | |___| (_| \__ \ |_| | |____| | (_| | | | | | |
#   |______\__,_|___/\__, |\_____|_|\__,_|_| |_| |_|
#                     __/ |
#                    |___/  By: d43m0n1k
EOF

sleep 2

# Prompt user to view license information
read -r -n 1 -t 5 -p "Press 'i' to view the license information: " input
if [[ "$input" == "i" || "$input" == "I" ]]; then
    # Copyright banner
    cat << "EOF"
################################################################################
# Copyright (C) 2024 d43m0n1k
#
# This program comes with ABSOLUTELY NO WARRANTY.
# This is free software, and you are welcome to redistribute it
# under certain conditions. See the GNU General Public License
# version 3 or later for details: https://www.gnu.org/licenses/gpl-3.0.html
#
# For more information, visit: https://github.com/d43m0n1k/EasyClam
################################################################################
EOF
else
    echo -e "\nSkipping license info..."
fi

# Function to check for root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root." | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Function to prompt the user for debug mode
prompt_debug_mode() {
    read -r -p "Do you want to enable debug mode? (yes/no): " debug_choice
    case $debug_choice in
        [yY]|[yY][eE][sS])
            DEBUG=true
            echo "Creating log file..."
            LOG_FILE="$(pwd)/EasyClam.log"  # Create log file when debug mode is enabled
            exec 2> >(tee -a "$LOG_FILE")   # Redirect standard error to log file with tee for real-time logging
            ;;
        *)
            DEBUG=false
            LOG_FILE="/dev/null"  # No log file when debug mode is disabled
            ;;
    esac
}

# Debug function
debug() {
    if [[ $DEBUG == "true" ]]; then
        echo "[DEBUG] $1" | tee -a "$LOG_FILE"
    fi
}

# Function to detect the package manager
detect_package_manager() {
    echo Identifying package manager details...
    debug "Detecting package manager..."
    local managers=("nala" "apt" "dnf" "yum" "zypper" "pacman" "apk")
    for manager in "${managers[@]}"; do
        if command -v "$manager" &> /dev/null; then
            PKG_MANAGER="$manager"
            debug "Package manager detected: $PKG_MANAGER"
            return
        fi
    done
    echo "No supported package manager found!" | tee -a "$LOG_FILE"
    exit 1
}

# Initialize a flag variable
system_update_flag=0

# Define the function you want to run only once
prompt_system_update() {
  if [ $system_update_flag -eq 0 ]; then
    read -r -p "Highly recommended to update system before installing, do you want to update? (yes/no): " update_choice
    if [[ "$update_choice" =~ ^(yes|y)$ ]]; then
        echo "Running system update..."
        case "$PKG_MANAGER" in
            "nala" | "apt" | "dnf" | "yum")
                sudo "$PKG_MANAGER" update -y && sudo "$PKG_MANAGER" upgrade -y
                ;;
            "zypper")
                sudo zypper -vvv dup
                ;;
            "pacman")
                sudo pacman -Syu
                ;;
            "apk")
                sudo apk update
                ;;
            *)
                echo "Warning: Unsupported package manager. System update may not work."
                ;;
        esac
        # Set the flag to indicate the function has run
        system_update_flag=1
    else
        echo "Skipping system update."
    fi
  else
    echo "System Update has already been run, skipping."
  fi
}

# Function to check if ClamAV is already installed
check_clamav_installed() {
    echo Checking if ClamAV is already installed...
    if ! command -v clamscan &> /dev/null; then
        echo "ClamAV is not currently installed..."
        read -r -p "Would you like to install it? (yes/no): " install_choice
        if [[ "$install_choice" =~ ^(yes|y)$ ]]; then
            install_clamav
            configure_freshclam
            setup_cron
        else
            echo "ClamAV installation skipped."
            exit 0
        fi
    else
        echo "ClamAV is already installed." | tee -a "$LOG_FILE"
        read -r -p "Would you like to reinstall, reconfigure, or remove it? (reinstall/reconfigure/remove/exit) " action_choice
        action_choice=$(echo "$action_choice" | tr '[:upper:]' '[:lower:]')
        case "$action_choice" in
            reinstall)
                echo Reinstalling ClamAV...
                remove_clamav
                install_clamav
                configure_freshclam
                setup_cron
                ;;
            reconfigure)
                echo Reconfiguring ClamAV...
                additional_setup_steps
                configure_freshclam
                setup_cron
                ;;
            remove)
                Removing ClamAV...
                remove_clamav
                exit 0 # Exit script after removing ClamAV
                ;;
            exit)
                echo "Exiting script." | tee -a "$LOG_FILE"
                exit 0
                ;;
            *)
                echo "Invalid choice. Exiting." | tee -a "$LOG_FILE"
                exit 1
                ;;
        esac
    fi
}

# Function to install clamav based on the detected package manager
install_clamav() {
    echo Installing ClamAV...
    prompt_system_update
    debug "Installing ClamAV using package manager: $PKG_MANAGER"
    case "$PKG_MANAGER" in
        "nala")
            sudo nala install -y clamav clamav-daemon
            ;;
        "apt")
            sudo apt install -y clamav clamav-daemon
            ;;
        "dnf")
            sudo dnf install -y clamav clamd clamav-update
            additional_setup_steps
            ;;
        "yum")
            sudo yum -y install clamav-server clamav-data clamav-update clamav-filesystem clamav clamav-lib clamav-server-systemd clamav-devel
            additional_setup_steps
            ;;
        "zypper")
            sudo zypper install -y clamav
            additional_setup_steps
            ;;
        "pacman")
            sudo pacman -Syu clamav
            ;;
        "apk")
            sudo apk add clamav
            additional_setup_steps
            ;;
        *)
            echo "Unsupported package manager: $PKG_MANAGER" | tee -a "$LOG_FILE"
            exit 1
            ;;
    esac
    debug "ClamAV installation complete."
}

# Function for additional setup steps
additional_setup_steps() {
    echo Enabling and starting ClamAV service...
    if command -v systemctl &> /dev/null; then
        sudo systemctl enable clamav-freshclam.service
        sudo systemctl start clamav-freshclam.service
    else
        echo "Systemctl not found. Please enable and start clamav-freshclam manually."
    fi
    echo "Performing SELinux configuration..."
    if command -v setsebool &> /dev/null; then
        sudo setsebool -P antivirus_can_scan_system 1
    fi
}

# Function to remove ClamAV
remove_clamav() {
    echo Removing ClamAV...
    case "$PKG_MANAGER" in
        "nala")
            sudo nala remove -y clamav clamav-daemon
            ;;
        "apt")
            sudo apt remove -y clamav clamav-daemon
            ;;
        "dnf")
            sudo dnf remove -y clamav clamd clamav-update
            ;;
        "yum")
            sudo yum -y remove clamav-server clamav-data clamav-update clamav-filesystem clamav clamav-lib clamav-server-systemd clamav-devel
            ;;
        "zypper")
            sudo zypper remove -y clamav
            ;;
        "pacman")
            sudo pacman -Rns clamav
            ;;
        "apk")
            sudo apk del clamav
            ;;
        *)
            echo "Unsupported package manager: $PKG_MANAGER" | tee -a "$LOG_FILE"
            exit 1
            ;;
    esac
    echo "ClamAV removed." | tee -a "$LOG_FILE"
}

# Function to configure freshclam
configure_freshclam() {
    echo Gathering info to configure freshclam...
    echo "Configuring freshclam..." | tee -a "$LOG_FILE"

    # Get the country code, default to US if detection fails
    country_code=$(curl -s ifconfig.co/country || echo "US")
    debug "Country code detected: $country_code"

    # List of potential locations for freshclam.conf
    config_files=(
        "/etc/clamav/freshclam.conf"
        "/etc/freshclam.conf"
        "/usr/local/etc/clamav/freshclam.conf"
        "/opt/local/etc/clamav/freshclam.conf"
    )

    file_found=false

    # Loop through the list and apply the sed command if the file exists
for config_file in "${config_files[@]}"; do
    if [ -f "$config_file" ]; then
        sudo sed -i "s/^#DatabaseMirror.*/DatabaseMirror db.${country_code}.clamav.net/" "$config_file"
        file_found=true
        break
    fi
done

if [ "$file_found" = false ]; then
    echo "Configuration file not found in the predefined locations."
    read -r -p "Would you like to search the entire filesystem for freshclam.conf? (y/n): " search_choice
    if [[ "$search_choice" =~ ^(yes|y)$ ]]; then
        # Run the find command from the root directory
        found_files=$(sudo find / -type f -name freshclam.conf 2>/dev/null)

        if [ -z "$found_files" ]; then
            echo "No freshclam.conf file found on the system."
        else
            echo "Found the following freshclam.conf files:"
            echo "$found_files"
            read -r -p "Please enter the full path of the freshclam.conf file you want to update: " config_file
            if [ -f "$config_file" ]; then
                sudo sed -i "s/^#DatabaseMirror.*/DatabaseMirror db.${country_code}.clamav.net/" "$config_file"
                echo "Updated $config_file successfully."
            else
                echo "The file path provided does not exist or is not a file."
            fi
        fi
    else
        echo "Search aborted."
    fi
fi

    sleep 2
    echo "Configuration of freshclam completed." | tee -a "$LOG_FILE"
}

# Function to setup cron job
setup_cron() {
    echo "Checking if cron is installed..."
    if ! command -v crond &> /dev/null && ! command -v cron &> /dev/null; then
        echo "Cron is not installed. Would you like to install it? (yes/no)"
        read -r install_cron_choice
        if [[ "$install_cron_choice" =~ ^[Yy]$ ]]; then
            echo "Installing cron..."
            case "$PKG_MANAGER" in
                "nala")
                    sudo nala install -y cron
                    ;;
                "apt")
                    sudo apt install -y cron
                    ;;
                "dnf")
                    sudo dnf install -y cronie cronie-anacron
                    ;;
                "yum")
                    sudo yum install -y cronie
                    ;;
                "zypper")
                    sudo zypper install -y cron
                    ;;
                "pacman")
                    sudo pacman -Sy --noconfirm cronie
                    ;;
                "apk")
                    sudo apk add cron
                    ;;
                *)
                    echo "No supported package manager found! Cannot install cron." | tee -a "$LOG_FILE"
                    exit 1
                    ;;
            esac
            echo "Cron installed successfully."
            
            # Enable and start the cron service
            if command -v systemctl &> /dev/null; then
                sudo systemctl enable --now crond || sudo systemctl enable --now cron
            elif command -v service &> /dev/null; then
                sudo service crond start || sudo service cron start
            else
                echo "Unable to start cron service. Please start it manually."
            fi
        else
            echo "Cron installation skipped."
            return
        fi
    else
        echo "Cron is already installed."
        # Ensure the cron service is running
        if command -v systemctl &> /dev/null; then
            sudo systemctl start crond || sudo systemctl start cron
        elif command -v service &> /dev/null; then
            sudo service crond start || sudo service cron start
        fi
    fi

    # Proceed with setting up the cron job for scans
    echo "Would you like to create a cron job for regular scans? (yes/no)"
    read -r create_cronjob
    if [[ "$create_cronjob" =~ ^[yY]$ ]]; then
        # Prompt for cron job schedule
        echo "Enter the time for the cron job (24-hour format, e.g., 01 for 1 AM):"
        read -r cron_hours
        echo "Enter the minutes for the cron job (0-59):"
        read -r cron_minutes
        echo "Enter the day(s) of the week for the cron job (0-6, where 0 is Sunday, 1 is Monday, ..., 6 is Saturday):"
        read -r cron_days
        
        # Combine hours, minutes, and days into the cron time format
        cron_time="$cron_minutes $cron_hours * * $cron_days"

        echo "Creating cron job to scan /home/ directories..."
        (sudo crontab -l 2>/dev/null; echo "$cron_time /usr/bin/clamscan -r --quiet --move=/home/$(whoami)/infected /home/") | sudo crontab -
        echo "Cron job created for scans at $cron_time on day(s) of the week $cron_days."
    else
        echo "Cron job creation for scans skipped."
    fi

    # Prompt for freshclam cron job
    echo "Would you like to add a daily update check for virus definitions using freshclam? (yes/no)"
    read -r create_freshclam_cronjob
    if [[ "$create_freshclam_cronjob" =~ ^[Yy]$ ]]; then
        echo "Configuring scheduled job for virus database updates..."
        local cron_file="/etc/cron.daily/freshclam"
        sudo bash -c "cat > $cron_file" << EOF
#!/bin/bash
# Freshclam auto-update script
/usr/bin/freshclam --quiet
EOF
        sudo chmod +x "$cron_file"
        echo "Cron job configured at $cron_file"
    else
        echo "Cron job creation for freshclam updates skipped."
    fi
}

# Main function to run the script
main() {
    check_root
    sleep 2
    prompt_debug_mode
    sleep 2
    detect_package_manager
    sleep 2
    check_clamav_installed
    sleep 2
    echo "Script execution completed." | tee -a "$LOG_FILE"
}

# Run the main function
main
sleep 2
exit 0
