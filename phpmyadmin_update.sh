#!/bin/bash

# --- MySQL Root Password (Optional Hardcoded Variable) ---
# If you want to hardcode the MySQL root password directly in this script,
# uncomment the line below and replace 'your_mysql_root_password_here' with your actual password.
# !!! IMPORTANT: If you use this, YOU MUST ensure this script file (e.g., /usr/local/bin/phpmyadmin.sh)
# has very strict permissions (e.g., 'chmod 600 /usr/local/bin/phpmyadmin.sh') to prevent unauthorized access.
# The script will attempt to set these permissions if this variable is used.
MYSQL_ROOT_PASSWORD="" # Set your password here, e.g., "myStrongRootPass"


# Configuration variables
PMA_DIR_DEFAULT="/var/www/phpmyadmin"
PMA_USER="www-data"
PMA_GROUP="www-data"
LOG_FILE="/var/log/update-phpmyadmin.log"
CURRENT_VERSION_INFO_URL="https://www.phpmyadmin.net/home_page/version.txt"
TEMP_DIR="/tmp/phpmyadmin_update_temp_$(date +%s)_$$"

# phpMyAdmin Control Database and User Configuration
PMA_CONTROL_DB="phpmyadmin"
PMA_CONTROL_USER="pma_admin"
PMA_CONTROL_HOST="localhost"
PMA_CONTROL_PASSWORD=""

# --- Functions ---

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

execute_mysql_query() {
    local query="$1"
    log "Executing MySQL query: $query"
    if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$query" 2>> "$LOG_FILE"; then
        log "Error: MySQL query failed. See $LOG_FILE for details."
        return 1
    fi
    return 0
}

execute_mysql_query_capture() {
    local query="$1"
    local output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -s -N -e "$query" 2>> "$LOG_FILE")
    if [ $? -ne 0 ]; then
        log "Error: MySQL query failed during capture attempt. See $LOG_FILE for details."
        return 1
    fi
    echo "$output"
    return 0
}

import_mysql_sql_file() {
    local db_name="$1"
    local sql_file="$2"
    log "Importing SQL file '$sql_file' into database '$db_name'..."
    if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "$db_name" < "$sql_file" 2>> "$LOG_FILE"; then
        log "Error: Failed to import SQL file '$sql_file' into '$db_name'. See $LOG_FILE for details."
        return 1
    fi
    return 0
}


# --- Main Script Logic ---

log "--- Starting phpMyAdmin update script ---"

# Track password origin to determine if it should be unset later
_MYSQL_ROOT_PASSWORD_ORIGIN_=""

# If MYSQL_ROOT_PASSWORD is set directly in this script, it has highest priority
if [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
    _MYSQL_ROOT_PASSWORD_ORIGIN_="HARDCODED"
    log "Using hardcoded MySQL root password from script variable."
    # Set script file permissions if hardcoded password is used
    SCRIPT_PATH="$(readlink -f "$0")"
    log "Hardcoded MySQL root password detected. Setting script permissions to 600 for '$SCRIPT_PATH'."
    chmod 600 "$SCRIPT_PATH" || log "Warning: Failed to set permissions for '$SCRIPT_PATH' to 600. Ensure this file is protected for security reasons."
fi


PMA_DIR="${1:-$PMA_DIR_DEFAULT}"
PMA_MYSQL_HOST="localhost"

if [ -n "$2" ]; then
    PMA_MYSQL_HOST="$2"
    log "Using provided MySQL host parameter: $PMA_MYSQL_HOST"
fi

# Determine MySQL root password, with priority: hardcoded (already checked), arg, env, interactive
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then # Only proceed if it wasn't hardcoded
    if [ -n "$3" ]; then
        MYSQL_ROOT_PASSWORD="$3"
        _MYSQL_ROOT_PASSWORD_ORIGIN_="ARGUMENT"
        log "Using MySQL root password from command-line argument."
    elif [ -n "${MYSQL_ROOT_PASSWORD}" ]; then # This will check the environment variable now
        _MYSQL_ROOT_PASSWORD_ORIGIN_="ENVIRONMENT"
        log "MYSQL_ROOT_PASSWORD environment variable is set. Will attempt validation."
    else
        _MYSQL_ROOT_PASSWORD_ORIGIN_="INTERACTIVE"
        log "No password provided via script variable, argument, or environment. Will prompt interactively."
    fi
fi

# Validate MySQL root password, with up to 3 interactive attempts if needed
ATTEMPTS=0
MAX_ATTEMPTS=3
PASSWORD_VALIDATED=false

# Only prompt if password is not already determined (or for subsequent interactive attempts)
while [ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ]; do
    # Only prompt if password is empty AND it was not hardcoded or passed as an argument initially
    if [ -z "$MYSQL_ROOT_PASSWORD" ] && { [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "INTERACTIVE" ] || [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "ENVIRONMENT" -a "$ATTEMPTS" -gt 0 ]; }; then
        echo "Please enter the MySQL root password (Attempt $((ATTEMPTS+1)) of $MAX_ATTEMPTS): "
        read -s MYSQL_ROOT_PASSWORD
        echo
        if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
            log "Warning: MySQL root password was not provided during interactive prompt."
            ATTEMPTS=$((ATTEMPTS+1))
            continue
        fi
    fi

    # If the password is still empty after prompting, and it was supposed to be interactive, exit.
    if [ -z "$MYSQL_ROOT_PASSWORD" ] && [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "INTERACTIVE" ]; then
        log "Error: MySQL root password was not provided. Aborting."
        exit 1
    fi

    log "Validating MySQL root password..."
    if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
        log "MySQL root password validated successfully."
        PASSWORD_VALIDATED=true
        break
    else
        log "Error: Invalid MySQL root password. Attempt $((ATTEMPTS+1)) failed."
        ATTEMPTS=$((ATTEMPTS+1))
        # Clear password only if it was obtained via environment or interactively for subsequent attempts
        if [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "ENVIRONMENT" ] || [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "INTERACTIVE" ]; then
            MYSQL_ROOT_PASSWORD=""
        fi
        if [ "$ATTEMPTS" -eq "$MAX_ATTEMPTS" ]; then
            log "Error: Maximum attempts reached. Unable to validate MySQL root password. Aborting."
            exit 1
        fi
    fi
done

if [ "$PASSWORD_VALIDATED" = false ]; then
    log "Error: MySQL root password could not be validated after $MAX_ATTEMPTS attempts. Aborting."
    exit 1
fi

log "phpMyAdmin installation directory set to: $PMA_DIR"
log "MySQL host for config set to: $PMA_MYSQL_HOST"


# Ensure phpMyAdmin directories exist and have correct initial permissions
log "Ensuring phpMyAdmin directories exist and have correct initial permissions..."
mkdir -p "$PMA_DIR" || { log "Error: Failed to create or access $PMA_DIR. Aborting."; exit 1; }
chown "${PMA_USER}:${PMA_GROUP}" "$PMA_DIR" || { log "Error: Failed to set ownership for $PMA_DIR. Aborting."; exit 1; }
chmod 755 "$PMA_DIR" || { log "Error: Failed to set permissions for $PMA_DIR. Aborting."; exit 1; }
log "Main directory $PMA_DIR created/verified."


# Get latest version information from phpMyAdmin website
VERSION_INFO=$(wget -qO- "$CURRENT_VERSION_INFO_URL") || { log "Error: Could not retrieve latest phpMyAdmin version information. Aborting."; exit 1; }

LATEST_VERSION=$(echo "$VERSION_INFO" | sed -n '1p')
DOWNLOAD_URL=$(echo "$VERSION_INFO" | sed -n '3p')

if [ -z "$LATEST_VERSION" ] || [ -z "$DOWNLOAD_URL" ]; then
    log "Error: Failed to parse latest version or download URL from version.txt. Aborting."
    exit 1
fi
log "Latest phpMyAdmin version available: $LATEST_VERSION"
log "Download URL from version.txt: $DOWNLOAD_URL"

# Check currently installed version
if [ -f "$PMA_DIR/VERSION" ]; then
    INSTALLED_VERSION=$(cat "$PMA_DIR/VERSION")
    log "Currently installed phpMyAdmin version: $INSTALLED_VERSION"
else
    INSTALLED_VERSION="none"
    log "No phpMyAdmin currently installed."
fi

# Exit if already up to date and installation seems complete
if [ "$LATEST_VERSION" = "$INSTALLED_VERSION" ] && [ -d "$PMA_DIR/libraries" ] && [ -f "$PMA_DIR/config.inc.php" ]; then
    log "phpMyAdmin is already up to date ($LATEST_VERSION) and configured. No full update needed."
    log "--- phpMyAdmin update script finished ---"
    
    # Unset MYSQL_ROOT_PASSWORD if it was not hardcoded in script or passed as argument
    if [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "ENVIRONMENT" ] || [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "INTERACTIVE" ]; then
        unset MYSQL_ROOT_PASSWORD
        log "MYSQL_ROOT_PASSWORD unset for this script's environment."
    fi
    exit 0
fi

log "Update required or initial installation. Proceeding to download $LATEST_VERSION..."

# Prepare unique temporary download/extraction directory
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR" || { log "Error: Failed to create temporary directory $TEMP_DIR. Aborting."; exit 1; }
chmod 700 "$TEMP_DIR"

DOWNLOAD_FILE=$(basename "$DOWNLOAD_URL")
CHECKSUM_FILE_URL="https://files.phpmyadmin.net/phpMyAdmin/${LATEST_VERSION}/${DOWNLOAD_FILE}.sha256"

# Download the phpMyAdmin archive
log "Downloading $DOWNLOAD_FILE to $TEMP_DIR..."
wget --quiet --show-progress -P "$TEMP_DIR" "$DOWNLOAD_URL" || { log "Error: Failed to download phpMyAdmin archive. Aborting."; rm -rf "$TEMP_DIR"; exit 1; }

# Download and verify SHA256 checksums
log "Downloading SHA256 checksum from $CHECKSUM_FILE_URL..."
wget --quiet -O "$TEMP_DIR/$DOWNLOAD_FILE.sha256" "$CHECKSUM_FILE_URL"
if [ $? -ne 0 ]; then
    log "Warning: Failed to download SHA256 checksum. Proceeding without SHA256 verification."
else
    EXPECTED_SHA256=$(cat "$TEMP_DIR/$DOWNLOAD_FILE.sha256" | awk '{print $1}')
    if [ -z "$EXPECTED_SHA256" ]; then
        log "Warning: SHA256 checksum for $DOWNLOAD_FILE not found in the downloaded file. Proceeding without verification."
    else
        ACTUAL_SHA256=$(sha256sum "$TEMP_DIR/$DOWNLOAD_FILE" | awk '{print $1}')
        if [ "$EXPECTED_SHA256" = "$ACTUAL_SHA256" ]; then
            log "SHA256 checksum verification successful for $DOWNLOAD_FILE."
        else
            log "Error: SHA256 checksum mismatch for $DOWNLOAD_FILE! Expected: $EXPECTED_SHA256, Actual: $ACTUAL_SHA256. **SECURITY RISK.** Aborting."
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    fi
fi

# Extract the archive
log "Extracting phpMyAdmin archive..."
unzip -q "$TEMP_DIR/$DOWNLOAD_FILE" -d "$TEMP_DIR" || { log "Error: Failed to extract phpMyAdmin archive. Aborting."; rm -rf "$TEMP_DIR"; exit 1; }

EXTRACTED_SOURCE_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "phpMyAdmin-$LATEST_VERSION-all-languages*" | head -n 1)
if [ -z "$EXTRACTED_SOURCE_DIR" ]; then
    log "Error: Could not find extracted phpMyAdmin directory. Aborting."
    rm -rf "$TEMP_DIR"
    exit 1
fi

TARGET_CONFIG_FILE="${PMA_DIR}/config.inc.php"

# Atomically replace current installation with the new version
log "Replacing current phpMyAdmin installation with new version..."
mv "$EXTRACTED_SOURCE_DIR" "${PMA_DIR}_new" || { log "Error: Failed to move extracted directory to ${PMA_DIR}_new. Aborting."; rm -rf "$TEMP_DIR"; exit 1; }

rm -rf "$PMA_DIR.bak"
if [ -d "$PMA_DIR" ]; then
    log "Backing up current phpMyAdmin installation to $PMA_DIR.bak"
    mv "$PMA_DIR" "$PMA_DIR.bak"
fi
log "Moving new phpMyAdmin version into place at $PMA_DIR"
mv "${PMA_DIR}_new" "$PMA_DIR"


# Post-Installation Directory and Permission Setup for 'tmp'
PMA_TMP_DIR="${PMA_DIR}/tmp"

log "Ensuring phpMyAdmin's 'tmp' directory is correctly set up in the new installation."
mkdir -p "$PMA_TMP_DIR" || { log "Error: Failed to create temporary directory $PMA_TMP_DIR after installation. Aborting."; rm -rf "$TEMP_DIR"; exit 1; }
chown "${PMA_USER}:${PMA_GROUP}" "$PMA_TMP_DIR" || { log "Error: Failed to set ownership for $PMA_TMP_DIR after installation. Aborting."; rm -rf "$TEMP_DIR"; exit 1; }
chmod 777 "$PMA_TMP_DIR" || { log "Error: Failed to set permissions for $PMA_TMP_DIR after installation. Aborting."; rm -rf "$TEMP_DIR"; exit 1; }
log "phpMyAdmin 'tmp' directory setup complete."


# Configuration File Handling
if [ ! -f "$TARGET_CONFIG_FILE" ]; then
    log "config.inc.php not found in $PMA_DIR. Creating from sample and applying initial settings."
    cp "$PMA_DIR/config.sample.inc.php" "$TARGET_CONFIG_FILE"
    
    GENERATED_SECRET=$(openssl rand -base64 32)
    sed -i "s|^\(\s*\)\(\$cfg\['blowfish_secret'\] = \)\(.*\)\(;.*$\)|\1\2'${GENERATED_SECRET}';|" "$TARGET_CONFIG_FILE"
    log "Generated and set blowfish_secret."

    sed -i "s|^\(\s*\)\(\$cfg\['Servers'\]\[\\\$i\]\['host'\] = \)\(.*\)\(;.*$\)|\1\2'${PMA_MYSQL_HOST}';|" "$TARGET_CONFIG_FILE"
    log "Set MySQL host to '${PMA_MYSQL_HOST}'."
else
    log "Existing config.inc.php found. It will be preserved. Checking/updating essential settings."
    
    if ! grep -q "\$cfg\['blowfish_secret'\]" "$TARGET_CONFIG_FILE" || \
       grep -q "^\s*\$cfg\['blowfish_secret'\] = '';" "$TARGET_CONFIG_FILE"; then
        GENERATED_SECRET=$(openssl rand -base64 32)
        if grep -q "\$cfg\['blowfish_secret'\]" "$TARGET_CONFIG_FILE"; then
            sed -i "s|^\(\s*\)\(\$cfg\['blowfish_secret'\] = \)\(.*\)\(;.*$\)|\1\2'${GENERATED_SECRET}';|" "$TARGET_CONFIG_FILE"
            log "Updated empty/existing blowfish_secret in config.inc.php."
        else
            sed -i "/\$cfg\['Servers'\]\[\$i\]\['host'\]/a \$cfg['blowfish_secret'] = '${GENERATED_SECRET}';" "$TARGET_CONFIG_FILE"
            log "Added missing blowfish_secret to existing config.inc.php."
        fi
    else
        log "blowfish_secret already present and set in config.inc.php."
    fi

    sed -i "s|^\(\s*\)\(\$cfg\['Servers'\]\[\\\$i\]\['host'\] = \)\(.*\)\(;.*$\)|\1\2'${PMA_MYSQL_HOST}';|" "$TARGET_CONFIG_FILE"
    log "Verified/updated MySQL host in existing config.inc.php to '${PMA_MYSQL_HOST}'."
fi


# MySQL Database and User Setup for phpMyAdmin Control Tables
log "Starting MySQL database and user setup for phpMyAdmin control tables..."

PMA_CONTROL_PASSWORD=$(openssl rand -base64 24 | head -c 16) 
log "Generated new password for phpMyAdmin control user (will be applied to MySQL and config)."

DB_EXISTS=$(execute_mysql_query_capture "SHOW DATABASES LIKE '$PMA_CONTROL_DB';" || true)
if [ -z "$DB_EXISTS" ]; then
    log "Database '$PMA_CONTROL_DB' does not exist. Creating it."
    if ! execute_mysql_query "CREATE DATABASE \`$PMA_CONTROL_DB\`;"; then exit 1; fi
else
    log "Database '$PMA_CONTROL_DB' already exists."
fi

USER_EXISTS=$(execute_mysql_query_capture "SELECT user FROM mysql.user WHERE user = '$PMA_CONTROL_USER' AND host = '$PMA_CONTROL_HOST';" || true)
if [ -z "$USER_EXISTS" ]; then
    log "User '$PMA_CONTROL_USER'@'$PMA_CONTROL_HOST' does not exist. Creating it with the generated password."
    if ! execute_mysql_query "CREATE USER '$PMA_CONTROL_USER'@'$PMA_CONTROL_HOST' IDENTIFIED BY '$PMA_CONTROL_PASSWORD';"; then exit 1; fi
else
    log "User '$PMA_CONTROL_USER'@'$PMA_CONTROL_HOST' already exists. Updating its password."
    if ! execute_mysql_query "ALTER USER '$PMA_CONTROL_USER'@'$PMA_CONTROL_HOST' IDENTIFIED BY '$PMA_CONTROL_PASSWORD';"; then exit 1; fi
fi

log "Granting necessary privileges to '$PMA_CONTROL_USER'@'$PMA_CONTROL_HOST' on database '$PMA_CONTROL_DB'."
if ! execute_mysql_query "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX ON \`$PMA_CONTROL_DB\`.* TO '$PMA_CONTROL_USER'@'$PMA_CONTROL_HOST';"; then exit 1; fi
if ! execute_mysql_query "FLUSH PRIVILEGES;"; then exit 1; fi
log "Privileges granted and flushed."


# Import create_tables.sql if phpmyadmin database tables are missing
PMA_SQL_FILE="$PMA_DIR/sql/create_tables.sql"
if [ ! -f "$PMA_SQL_FILE" ]; then
    log "Error: phpMyAdmin SQL file '$PMA_SQL_FILE' not found. Cannot import control tables. Aborting."
    exit 1
fi

TABLES_IN_PMA_DB=$(execute_mysql_query_capture "SHOW TABLES FROM \`$PMA_CONTROL_DB\`;" || true)
if [ -z "$TABLES_IN_PMA_DB" ]; then
    log "No tables found in '$PMA_CONTROL_DB'. Importing '$PMA_SQL_FILE'."
    if ! import_mysql_sql_file "$PMA_CONTROL_DB" "$PMA_SQL_FILE"; then exit 1; fi
else
    log "Tables already exist in '$PMA_CONTROL_DB'. Skipping import of '$PMA_SQL_FILE'."
fi

# Update config.inc.php with control user settings
log "Updating '$TARGET_CONFIG_FILE' with phpMyAdmin control user and database settings."

sed -i "s|^\(\s*\)\(\$cfg\['Servers'\]\[\$i\]\['pmadb'\] = \)\(.*\)\(;.*$\)|\1\2'$PMA_CONTROL_DB';|" "$TARGET_CONFIG_FILE"
sed -i "s|^\(\s*\)\(\$cfg\['Servers'\]\[\$i\]\['controluser'\] = \)\(.*\)\(;.*$\)|\1\2'$PMA_CONTROL_USER';|" "$TARGET_CONFIG_FILE"
sed -i "s|^\(\s*\)\(\$cfg\['Servers'\]\[\$i\]\['controlpass'\] = \)\(.*\)\(;.*$\)|\1\2'$PMA_CONTROL_PASSWORD';|" "$TARGET_CONFIG_FILE"

PMA_TABLE_KEYS=(
    "bookmarktable" "relation" "table_info" "table_coords" "pdf_pages"
    "column_info" "history" "recent" "favorite" "users" "usergroups"
    "navigationhiding" "savedsearches" "central_columns" "designer_coords"
    "tracking" "userconfig"
)

for table_key in "${PMA_TABLE_KEYS[@]}"; do
    sed -i "s|^\(\s*\)//\s*\(\$cfg\['Servers'\]\[\$i\]\['$table_key'\]\s*=\s*'.*'[^;]*;\s*\)|\1\2|" "$TARGET_CONFIG_FILE"
done

log "phpMyAdmin control user and database settings applied to '$TARGET_CONFIG_FILE'."

# Final Ownership and Permissions for the entire phpMyAdmin directory
log "Setting final ownership and permissions for the entire "$PMA_DIR"..."
chown -R "${PMA_USER}:${PMA_GROUP}" "$PMA_DIR"
find "$PMA_DIR" -type d -exec chmod 755 {} +
find "$PMA_DIR" -type f -exec chmod 644 {} +

echo "$LATEST_VERSION" | tee "$PMA_DIR/VERSION" > /dev/null

log "phpMyAdmin "$LATEST_VERSION" successfully installed/updated and configured."

# --- Cleanup ---
log "Cleaning up temporary directory: "$TEMP_DIR" and old backup: "$PMA_DIR".bak"
rm -rf "$TEMP_DIR"
rm -rf "$PMA_DIR.bak"

# Unset MYSQL_ROOT_PASSWORD if it was not hardcoded in script or passed as argument
if [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "ENVIRONMENT" ] || [ "$_MYSQL_ROOT_PASSWORD_ORIGIN_" == "INTERACTIVE" ]; then
    unset MYSQL_ROOT_PASSWORD
    log "MYSQL_ROOT_PASSWORD unset for this script's environment."
fi

log "--- phpMyAdmin update script finished ---"
