# Automated phpMyAdmin Installer and Updater

This Bash script automates the process of installing or updating phpMyAdmin on a Debian/Ubuntu-based web server. It handles downloading the latest version, verifying checksums, configuring the web directory, setting up necessary MySQL database and user for phpMyAdmin's control features, and managing file permissions.

## Features

* **Automatic Latest Version Download**: Fetches the latest stable phpMyAdmin release directly from `phpmyadmin.net`.

* **SHA256 Checksum Verification**: Ensures the integrity and authenticity of the downloaded archive.

* **Atomic Installation/Update**: Replaces the old phpMyAdmin installation with the new one safely by creating a temporary backup.

* **Automated MySQL Setup**:

    * Creates a dedicated `phpmyadmin` database if it doesn't exist.

    * Creates or updates a specific control user (`pma_admin`) with a strong, automatically generated password.

    * Grants the `pma_admin` user the necessary privileges on the `phpmyadmin` database.

    * Imports phpMyAdmin's control tables (`create_tables.sql`) into the `phpmyadmin` database, but only if they don't already exist.

* **`config.inc.php` Configuration**: Automatically sets `blowfish_secret`, MySQL host, and configures the control user (`pma_admin`) for phpMyAdmin's advanced features (e.g., bookmarks, history).

* **Permission Management**: Sets appropriate ownership (`www-data:www-data`) and file permissions (`755` for directories, `644` for files) for the phpMyAdmin installation.

* **Logging**: All actions and errors are logged to `/var/log/update-phpmyadmin.log`.

## Prerequisites

Before running this script, ensure the following are installed on your Debian/Ubuntu system:

* `wget`: For downloading files.

* `unzip`: For extracting the phpMyAdmin archive.

* `mysql-client`: The MySQL client utilities (required for `mysql` command).

* `openssl`: For generating random passwords and `blowfish_secret`.

* `php-mbstring` (and other PHP extensions required by phpMyAdmin, e.g., `php-mysqli`, `php-json`, `php-gd`, `php-zip`, `php-curl`, `php-xml`): Ensure your PHP installation has these extensions enabled. While the script doesn't install them, they are crucial for phpMyAdmin's functionality.

## Hardcoded Configuration Variables

The script allows you to hardcode certain configuration parameters directly within the script file itself. Using these variables takes the highest precedence over values provided via command-line arguments or environment variables.

**Important Security Note**: If you hardcode sensitive information like passwords, ensure the script file has very strict permissions (e.g., `chmod 600 /usr/local/bin/phpmyadmin.sh`) to prevent unauthorized access. The script attempts to set these permissions automatically if `MYSQL_ADMIN_PASSWORD_HARDCODED` is used.

* **`MYSQL_ADMIN_USER_HARDCODED`**:
    * Set your MySQL administrative username here (e.g., `"my_mysql_admin"`).
    * Leave empty (`""`) if you prefer to provide the username via command-line argument or use the default (`root`).

* **`MYSQL_ADMIN_PASSWORD_HARDCODED`**:
    * Set your MySQL administrative password here (e.g., `"myStrongAdminPass"`).
    * Leave empty (`""`) if you prefer to provide the password via command-line argument, environment variable, or interactive prompt.

* **`PMA_MYSQL_HOST_HARDCODED`**:
    * Set your MySQL host here (e.g., `"192.168.1.100"` or `"db.example.com"`).
    * This will override any host provided via the command-line argument.
    * Leave empty (`""`) if you prefer to provide the host via command-line argument or use the default (`localhost`).

## Usage

1.  **Save the Script**:
    Save the script content to a file, for example, `/usr/local/bin/phpmyadmin.sh`.

2.  **Make Executable**:

    ```bash
    sudo chmod +x /usr/local/bin/phpmyadmin.sh
    ```

3.  **Run the Script**:

    The script accepts optional parameters:

    `sudo /usr/local/bin/phpmyadmin.sh [PMA_INSTALL_DIR] [MYSQL_HOST] [MYSQL_ADMIN_USER] [MYSQL_ADMIN_PASSWORD]`

    * **`PMA_INSTALL_DIR` (Optional)**: The directory where phpMyAdmin will be installed.

        * Default: `/var/www/phpmyadmin`

        * Example: `/usr/share/phpmyadmin`

    * **`MYSQL_HOST` (Optional)**: The MySQL host to configure in phpMyAdmin's `config.inc.php`. This is also the host the script will attempt to connect to for MySQL administrative operations.
        * **Note**: This argument is superseded by `PMA_MYSQL_HOST_HARDCODED` if that variable is set in the script.
        * Default: `localhost` (if not specified via hardcoded variable or this argument).
        * Example: `127.0.0.1` or `my.remote.mysql.server`

    * **`MYSQL_ADMIN_USER` (Optional)**: The username for the MySQL administrative user.
        * **Note**: This argument is superseded by `MYSQL_ADMIN_USER_HARDCODED` if that variable is set in the script.
        * Default: `root` (if not specified via hardcoded variable or this argument).

    * **`MYSQL_ADMIN_PASSWORD` (Optional)**: The password for the MySQL administrative user (`MYSQL_ADMIN_USER`).
        * **Note**: This argument is superseded by `MYSQL_ADMIN_PASSWORD_HARDCODED` if that variable is set in the script.
        * See "MySQL Administrative User and Password Handling" below for detailed explanation of how the script obtains this password.

### Examples:

* **Default installation (will prompt for MySQL root password)**:

    ```bash
    sudo /usr/local/bin/phpmyadmin.sh
    ```

* **Specify installation directory**:

    ```bash
    sudo /usr/local/bin/phpmyadmin.sh /var/www/html/pma
    ```

* **Specify MySQL host (e.g., a remote container/VM)**:

    ```bash
    sudo /usr/local/bin/phpmyadmin.sh /var/www/phpmyadmin 192.168.1.100
    ```

* **Provide MySQL administrative user and password via command-line arguments**:

    ```bash
    sudo /usr/local/bin/phpmyadmin.sh /var/www/phpmyadmin localhost my_admin_user MySecureAdminPass123
    ```

* **Provide MySQL administrative password via environment variable (using default `root` user)**:

    ```bash
    export MYSQL_ADMIN_PASSWORD="MySecureAdminPass123"
    sudo /usr/local/bin/phpmyadmin.sh
    ```

    (Remember to `unset MYSQL_ADMIN_PASSWORD` after execution for security.)

* **Using hardcoded variables in the script**:
    Refer to the "Hardcoded Configuration Variables" section above for how to set `MYSQL_ADMIN_USER_HARDCODED`, `MYSQL_ADMIN_PASSWORD_HARDCODED`, or `PMA_MYSQL_HOST_HARDCODED` directly in the script. When these are set, the corresponding command-line arguments can be omitted or left as empty strings.

    Example if `PMA_MYSQL_HOST_HARDCODED` is set in the script:
    ```bash
    sudo /usr/local/bin/phpmyadmin.sh /var/www/phpmyadmin "" root MySecureRootPass123
    ```
    (Note the empty string `""` for the `MYSQL_HOST` argument, as it's now overridden by the hardcoded variable.)

### Scheduling with Cron

You can schedule this script to run automatically at regular intervals (e.g., weekly) using `cron`. This ensures your phpMyAdmin installation stays up-to-date.

1.  **Open Crontab**:
    Open your `cron` table for editing. If you are scheduling this script to run as `root` (which is necessary for the MySQL operations), use `sudo crontab -e`.

    ```bash
    sudo crontab -e
    ```

2.  **Add a Cron Job Entry**:
    Add the following line to the end of the file. This example schedules the script to run every Sunday at midnight (00:00).

    ```cron
    0 0 * * 0 /usr/local/bin/phpmyadmin.sh >> /var/log/phpmyadmin_cron.log 2>&1
    ```

    * `0`: Minute (0-59)

    * `0`: Hour (0-23)

    * `*`: Day of month (1-31)

    * `*`: Month (1-12)

    * `0`: Day of week (0-7, where 0 and 7 are Sunday)

    * `/usr/local/bin/phpmyadmin.sh`: Path to your script.

    * `>> /var/log/phpmyadmin_cron.log 2>&1`: Redirects all standard output and errors to a separate cron log file, preventing email notifications from cron and allowing you to review the scheduled run's output.

    **Important Considerations for Cron and Passwords**:

    * If your `MYSQL_ADMIN_PASSWORD` is hardcoded in the script (see "Hardcoded Configuration Variables"), ensure the script's permissions are strictly set to `600` (`chmod 600`) as mentioned in that section.

    * **Do NOT** include the MySQL administrative password directly in the cron entry. The script's internal password handling (hardcoded in script, environment variable, or interactive prompt) will manage this. Since cron jobs run non-interactively, if the password is not hardcoded or passed via environment variable, the script will **fail** to prompt for it and will abort. Therefore, for cron, either hardcode the password (with strict permissions) or ensure `MYSQL_ADMIN_PASSWORD` is available in the cron job's environment (e.g., by sourcing a file that sets it, though hardcoding in the script is simpler for cron).

3.  **Save and Exit**:
    Save the `crontab` file (usually `Ctrl+X`, then `Y`, then `Enter` in `nano`).

## MySQL Administrative User and Password Handling

The script requires a MySQL user with administrative privileges to perform critical database operations:

* Creating the `phpmyadmin` control database.

* Creating or updating the `pma_admin` control user.

* Granting privileges to the `pma_admin` user.

* Importing the necessary control tables.

The script attempts to obtain the MySQL administrative username and password in the following order of precedence:

**For Username (`MYSQL_ADMIN_USER`):**
1.  **Hardcoded in the script**: If `MYSQL_ADMIN_USER_HARDCODED` is set (see "Hardcoded Configuration Variables").
2.  **Command-line argument**: If provided as the third argument when executing the script.
3.  **Default**: If not provided by the above methods, it defaults to `root`.

**For Password (`MYSQL_ADMIN_PASSWORD`):**
1.  **Hardcoded in the script**: If `MYSQL_ADMIN_PASSWORD_HARDCODED` is set (see "Hardcoded Configuration Variables").
2.  **Command-line argument**: If provided as the fourth argument when executing the script.
3.  **Environment variable**: If the `MYSQL_ADMIN_PASSWORD` environment variable is exported before running the script.
4.  **Interactive prompt**: If the password is not found through any of the above methods, the script will interactively prompt you to enter it.

    * You will have up to **3 attempts** to enter the correct password. This helps prevent accidental typos (e.g., wrong keyboard layout or CapsLock). If all attempts fail, the script will abort.

### Security Best Practices for Passwords:

* **Avoid hardcoding in production**: For maximum security, avoid hardcoding passwords directly in the script file. If you do, strictly control file permissions.

* **Use environment variables temporarily**: If using environment variables, `unset` them immediately after the script completes to clear them from your shell's environment. The script attempts to `unset` the variable if it sourced it from the environment or interactively.

* **Restrict script permissions**: Regardless of how you provide the password, always ensure your script file has strict permissions (`chmod 600`) if it contains sensitive information or you are running it as `root`.

## phpMyAdmin Control User (`pma_admin`)

This script creates or updates a dedicated MySQL user named `pma_admin` (with `localhost` host) and a database named `phpmyadmin`. This user and database are essential for phpMyAdmin's advanced features, such as:

* **User preferences storage**: Saving custom settings for each phpMyAdmin user.

* **Bookmark queries**: Storing frequently used SQL queries.

* **Relation transformations**: Defining relationships between tables.

* **History**: Keeping a record of executed SQL commands.

The `pma_admin` user's password is automatically generated by the script and securely stored within phpMyAdmin's `config.inc.php` file. If the `pma_admin` user already exists (e.g., from a previous manual setup or migration), the script will update its password to the newly generated one and configure `config.inc.php` accordingly to ensure consistency. The control tables (`create_tables.sql`) are imported only if the `phpmyadmin` database is empty.

## Logging

All script output, including actions performed and any errors encountered, is logged to:
`/var/log/update-phpmyadmin.log`

This file is useful for debugging and reviewing the script's execution history.
л
