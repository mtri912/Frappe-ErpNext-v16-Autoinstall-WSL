Frappe & ERPNext Auto-Installer for WSL
=======================================

Welcome to the Frappe & ERPNext Auto-Installer for Windows Subsystem for Linux (WSL)! This script automates the installation of Frappe Framework and optionally ERPNext and HRMS on your WSL environment, making it easy to get started with development or testing.

🌟 Features
-----------

-   Automated Installation: Installs Frappe Framework version 15 on WSL with minimal input.

-   Optional Apps: Choose to install ERPNext and/or HRMS during the setup.

-   Custom Configuration: Generates a unique identifier to prevent conflicts with existing installations.

-   MariaDB Configuration: Sets up MariaDB 10.6 with secure settings.

-   Environment Setup: Installs all necessary dependencies including Node.js, Redis, and wkhtmltopdf.

-   User-Friendly Prompts: Guides you through the setup with clear and friendly prompts.

📦 Prerequisites
----------------

-   Windows Subsystem for Linux (WSL) installed on your Windows machine.

-   Ubuntu 22.04 LTS or a compatible Linux distribution running in WSL.

-   No other WSL instances running Frappe benches. Ensure all other WSL instances with benches are closed before running the installer.

🚀 Installation
---------------

Follow these steps to install Frappe and optionally ERPNext and HRMS on your WSL environment.

### 1\. Clone the Repository

Open your WSL terminal and clone the repository:

```
git clone https://github.com/kamikazce/Frappe-ErpNext-Autoinstall-WSL.git
cd Frappe-ErpNext-Autoinstall-WSL
```

### 2\. Make the Installer Executable

```
chmod +x install.sh
```

### 3\. Run the Installer

Execute the installer script with root privileges:

```
sudo ./install.sh
```

🛠 Usage
--------

The installer will guide you through several prompts:

1.  **Create a New User:** You can choose to create a new system user or use the current one.

2.  **MariaDB Root Password:** Set a password for the MariaDB root user.

3.  **Administrator Password:** Set a password for the Frappe administrator account.

4.  **Site Name:** Specify the name of the new Frappe site.

5.  **Install ERPNext:** Choose whether to install the ERPNext application.

6.  **Install HRMS:** Choose whether to install the HRMS application.

### 4\. Starting the Bench

After the installation is complete, switch to the specified user and start the bench:

```
sudo su - your_username
cd /var/bench/frappe-bench15_a3b99f84/
bench start
```

-   Replace `your_username` with the username you selected during installation.

-   Replace `a3b99f84` with the unique identifier generated during installation.

### 5\. Accessing Your Site

Open your web browser and navigate to:

```
http://localhost:8000
```

Log in using:

-   **Username:** `Administrator`

-   **Password:** The administrator password you set during installation.

⚠ Important Notes
-----------------

-   **Close Other WSL Instances:** Before running the installer, ensure that no other WSL instances with Frappe benches are running. Having multiple benches running simultaneously can cause conflicts and prevent `bench start` from working correctly.

-   **MariaDB Service:** The installer starts MariaDB manually due to WSL limitations. Ensure MariaDB is running when you need it.

-   **Permissions:** If you encounter any permissions issues, verify that directories and files have the correct ownership (`mysql:mysql` for MariaDB data directories).

🐞 Troubleshooting
------------------

### 🛠 MariaDB Troubleshooting (ID: a3b99f84)

If you encounter issues with MariaDB, use the following steps to stop, start, and restart it properly:

#### **Stop MariaDB:**

```
sudo kill $(cat /run/mysqld/mysqld_a3b99f84.pid)
sudo pkill -f mysqld
```

#### **Start MariaDB:**

```
mysqld_safe --defaults-file=/etc/mysql/mariadb.conf.d/99-custom_a3b99f84.cnf &
```

#### **Check if MariaDB is Running:**

```
mysqladmin --socket="/var/run/mysqld/mysqld_a3b99f84.sock" ping
```

If it returns `**mysqld is alive**`, the database is running.

#### **Create a Quick Restart Script:**

To simplify MariaDB restarts, create a restart script:

```
echo '#!/bin/bash
sudo kill $(cat /run/mysqld/mysqld_a3b99f84.pid) 2>/dev/null
sudo pkill -f mysqld
sleep 2
mysqld_safe --defaults-file=/etc/mysql/mariadb.conf.d/99-custom_a3b99f84.cnf &
' | sudo tee /usr/local/bin/restart-mariadb > /dev/null
sudo chmod +x /usr/local/bin/restart-mariadb
```

Now you can restart MariaDB anytime with:

```
sudo restart-mariadb
```

#### **Autostart MariaDB on WSL Startup:**

1.  **Edit or create WSL configuration file:**

```
sudo nano /etc/wsl.conf
```

1.  **Add the following:**

```
[boot]
command="/etc/init.d/start-mariadb"
```

1.  **Create a startup script:**

```
echo '#!/bin/bash
CONFIG_FILE="/etc/mysql/mariadb.conf.d/99-custom_a3b99f84.cnf"
SOCKET_FILE="/var/run/mysqld/mysqld_a3b99f84.sock"

mkdir -p /var/run/mysqld
chown -R mysql:mysql /var/run/mysqld

if [ -S "$SOCKET_FILE" ]; then
    echo "MariaDB is already running."
else
    echo "Starting MariaDB..."
    mysqld_safe --defaults-file="$CONFIG_FILE" &
    echo "MariaDB started."
fi' | sudo tee /etc/init.d/start-mariadb > /dev/null
sudo chmod +x /etc/init.d/start-mariadb
```

1.  **Restart WSL:**

    ```
    exit
    wsl --shutdown
    wsl -d Dev
    ```

2.  **Verify MariaDB:**

    ```
    mysqladmin --socket="/var/run/mysqld/mysqld_a3b99f84.sock" ping
    ```

    If it returns `**mysqld is alive**`, the autostart is configured correctly.

💡 Port Conflicts
-----------------

If port `8000` is already in use, you can specify a different port when starting the bench:

```
bench start --port 8001
```

🤝 Contributing
---------------

We welcome contributions! If you have suggestions for improvements or encounter any issues, feel free to open an issue or submit a pull request on GitHub.

