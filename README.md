# Dual-boot NTFS Pong (NTFS Watch & Repair)

This project provides an automated "Ping-Pong" repair workflow for NTFS partitions shared between Linux and Windows in a dual-boot environment **based on Grub2Win**.
# NTFS Auto-Repair 

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange)](https://ubuntu.com)
[![License](https://img.shields.io/github/license/dominatos/dual-boot-NTFS-Pong)](LICENSE)

**Automatic NTFS repair on power loss without manual intervention**


When Linux detects that an NTFS partition is corrupted (read-only or mount failure), it automatically reboots the system into Windows to run `chkdsk`, and then Windows automatically reboots back into Linux after the repair.

## 🔄 How It Works

1.  **Detection (Linux)**: The `ntfs-watch.timer` runs `ntfs_watch_and_repair.sh` periodically.
2.  **Validation**: It checks if the watched NTFS mount (e.g., `/mnt/ftp`) is accessible.
    -   If valid: Exits quietly.
    -   If invalid: Tries basic `ntfsfix`.
3.  **escalation**: If `ntfsfix` fails:
    -   It mounts the Windows partition.
    -   It modifies `grub.cfg` (used by Grub2Win) to set the **default boot entry to Windows (Index 0)**.
    -   It creates a "repair flag" file on the Windows drive.
    -   It reboots the system.
4.  **Repair (Windows)**:
    -   Windows boots. A scheduled task runs `chkdisk.bat`.
    -   `chkdisk.bat` runs `chkdsk /f` on the target drive.
    -   `chkdisk.bat` updates `grub.cfg` to set the **default boot entry back to Linux (Index 1)**.
    -   `chkdisk.bat` sets a "Reboot Flag" (`reboot.txt`) to "1".
5.  **Return (Windows -> Linux)**:
    -   A second scheduled task (or a loop) runs `reboot-from-file.bat`.
    -   This script checks `reboot.txt`. If "1", it initiates the reboot, sending the system back to Linux.
    -   *Note: This split logic allows for maintenance windows or checking results before rebooting.*

## 📋 Prerequisites

### Linux
-   **OS**: Any **systemd-based** Linux distribution (e.g., Ubuntu, Debian, Fedora, Arch, CentOS).
-   **Packages**: `ntfs-3g`, `curl` (for Telegram notifications).
-   **Sudo/Root**: Scripts run as root via systemd.

### Windows
-   **OS**: Windows 10 or 11.
-   **Bootloader**: **Grub2Win** must be installed and managing the boot process.
    -   To ensure this works, **Windows must be Menu Entry 0** and **Linux must be Menu Entry 1** in your Grub2Win configuration.
-   **Fast Startup**: **MUST BE DISABLED** to prevent NTFS hibernation locks.
    -   *Power Options > Choose what the power buttons do > Change settings that are currently unavailable > Uncheck "Turn on fast startup"*.

## ⚙️ Configuration

### ✅ Quick Start Checklist (MUST EDIT)

**Note:** If you run `sudo ./install.sh`, step 1 and 3 are handled for you automatically!

Before running anything *manually*, you **MUST** modify the following scripts to match your system's UUIDs and paths.

1.  **`ntfs_watch_and_repair.sh`** (Linux):
    -   *Managed by `/etc/ntfs-watch.conf` if installed via `install.sh`.*
    -   `FTP_MOUNT_POINT`: Your NTFS mount path (e.g., `/mnt/ftp`).
    -   `FTP_DISC`: The NTFS partition device (e.g., `/dev/sda1`).
    -   `WIN_DEV`: The Windows system partition (e.g., `/dev/sdc3`).
    -   `WIN_MOUNT_POINT`: Temporary mount point for Windows C: drive.
2.  **`chkdisk.bat`** (Windows):
    -   `DISK_LETTER`: The Windows drive letter of the partition to repair (e.g., `D`).
    -   `GRUB_CFG`: Path to your Grub2Win config file.
3.  **Telegram (Optional)**:
    -   Update `TG_TOKEN` and `CHAT_ID` in `tg_send.bat` and `ntfs_watch_and_repair.sh` (or `tg_send` script).

### 🛡️ Recommended `fstab` Configuration

To prevent your Linux system from failing to boot if the NTFS drive is corrupted or missing, use the `nofail` and `x-systemd.automount` options in your `/etc/fstab`.

**Example:**
```fstab
# <file system>        <mount point>  <type>  <options>                                                   <dump>  <pass>
UUID=0509747065D54FFA  /mnt/ftp       ntfs3   uid=1001,gid=1001,umask=0002,noatime,nofail,x-systemd.automount 0       0
```

-   **`nofail`**: The system will not hang if this drive is missing or damaged.
-   **`x-systemd.automount`**: The drive is mounted only when accessed, further reducing boot risks.

### 1. Linux Setup (`ntfs_watch_and_repair.sh`)

Edit the variables at the top of the script:

```bash
FTP_MOUNT_POINT="/mnt/ftp"      # The NTFS mount to watch
FTP_DISC="/dev/sda1"            # Physical partition of the NTFS drive
WIN_DEV="/dev/sdc3"             # Windows system partition (where grub.cfg lives)
WIN_MOUNT_POINT="/mnt/win"      # Temporary mount point for Windows C:
GRUB_CFG="${WIN_MOUNT_POINT}/grub2/grub.cfg" # Path to Grub2Win config
```

### 2. Windows Setup (`chkdisk.bat`)

Edit the variables at the top of the batch file:

```batch
set "DISK_LETTER=D"             :: The drive letter of the NTFS partition to repair
set "GRUB_CFG=C:\grub2\grub.cfg" :: Path to Grub2Win config
set "LOG=C:\chkdisk.log"        :: Log file path
```

### 3. Telegram Notifications (Optional)

Both Linux and Windows scripts support sending logs to Telegram.

-   **Linux**: Edit `ntfs_watch_and_repair.sh` or ensure `tg_send` is in your PATH.
-   **Windows**: Edit `tg_send.bat` with your `TG_TOKEN` and `CHAT_ID`.

## 🚀 Installation

### Linux (Automated via Installer)

The easiest way to install is using the interactive installer:

```bash
chmod +x install.sh
sudo ./install.sh
```
Follow the on-screen prompts to select your partitions and set up Telegram notifications.

### Linux (Manual)

If you prefer to install manually:

1.  **Install Scripts**:
    ```bash
    sudo cp ntfs_watch_and_repair.sh /usr/local/sbin/
    sudo chmod +x /usr/local/sbin/ntfs_watch_and_repair.sh
    # If using the standalone tg_send script:
    sudo cp tg_send /usr/local/bin/
    sudo chmod +x /usr/local/bin/tg_send
    ```

2.  **Configuration**:
    Create `/etc/ntfs-watch.conf` manually:
    ```bash
    FTP_DISC="/dev/sda1"
    FTP_MOUNT_POINT="/mnt/ftp"
    WIN_DEV="/dev/sdc3"
    # Optional
    TG_TOKEN="your_token"
    CHAT_ID="your_chat_id"
    ```

3.  **Install Service & Timer**:
    ```bash
    sudo cp ntfs-watch.service /etc/systemd/system/
    sudo cp ntfs-watch.timer /etc/systemd/system/
    ```

4.  **Enable Automation**:
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable --now ntfs-watch.timer
    ```

### Optional: Paragon UFSD (`chkntfs`) for Linux Repair

To enable the script to attempt repairs *within* Linux before rebooting to Windows, install the Paragon UFSD tools.

1.  **Download APK**: Get `paragon-ufsd-root-mounter-X.X.X.apk` from [APKMirror](https://www.apkmirror.com/apk/paragon-technologie-gmbh/paragon-ufsd-root-mounter/#google_vignette).
2.  **Extract & Install**:
    ```bash
    mkdir ~/ufsd && cd ~/ufsd
    unzip paragon-ufsd-root-mounter-*.apk -d .
    sudo cp assets/x86/chkufsd /usr/local/bin/chkntfs
    sudo chmod +x /usr/local/bin/chkntfs
    
    # Create symlinks for compatibility
    sudo ln -sf /usr/local/bin/chkntfs /usr/local/bin/chkufsd
    sudo ln -sf /usr/local/bin/chkntfs /usr/local/bin/ufsd
    sudo ln -sf /usr/local/bin/chkntfs /usr/local/bin/mount_ufsd_fuse
    ```
3.  **Verify**:
    ```bash
    chkntfs --version
    ```

### Windows

1.  **Place Files**:
    -   Copy `chkdisk.bat`, `reboot-from-file.bat`, `tg_send.bat` to `C:\`.
    -   Ensure `C:\grub2\grub.cfg` exists.

3.  **Automate with Task Scheduler**:
    Create a **single** task that runs both scripts sequentially to ensure the correct order.

    1.  Open **Task Scheduler**.
    2.  Create a new Task named **"NTFS Repair Automation"**.
    3.  **General Tab**:
        -   Select **"Run whether user is logged on or not"** (or "Run only when user is logged on" if you prefer).
        -   Check **"Run with highest privileges"** (Required for chkdsk).
    4.  **Triggers Tab**:
        -   New Trigger -> **"At log on"** (or "At Startup").
    5.  **Actions Tab**:
        -   **Action 1**: Start a program -> `C:\chkdisk.bat`
        -   **Action 2**: Start a program -> `C:\reboot-from-file.bat`
    6.  **Conditions Tab**:
        -   Uncheck "Start the task only if the computer is on AC power" (optional, but recommended for laptops).
    7.  Save.

    **Why separate actions?**
    Task Scheduler executes actions sequentially. This ensures `chkdisk.bat` completes its repair work and sets the flag *before* `reboot-from-file.bat` runs to check that flag.

## 🛡️ Loop Prevention Logic

To prevent the system from getting stuck in an infinite reboot loop between Windows and Linux, the scripts use a "Flag File" (`reboot.txt` on the Windows drive).

1.  **Normal Boot (Manual)**:
    -   Flag is logically `0` (or file doesn't exist).
    -   You boot Windows manually from Grub.
    -   `chkdisk.bat` runs, sees Flag=0, prints "Manual Mode", and **exits**.
    -   `reboot-from-file.bat` runs, sees Flag=0, and **does nothing**.
    -   *Result: Windows stays open.*

2.  **Repair Boot (Automated)**:
    -   Linux detects breakage. It sets Flag=`1` and reboots.
    -   Windows boots.
    -   `chkdisk.bat` runs, sees Flag=1, performs `chkdsk`.
    -   `chkdisk.bat` updates `grub.cfg` to set default boot to **Linux (Index 1)**.
    -   `chkdisk.bat` ensures Flag=`1` is set at the end.
    -   `reboot-from-file.bat` runs, sees Flag=1. It **resets Flag to 0** and triggers a **Reboot**.
    -   *Result: System reboots back to Linux.*

## 📂 File Structure

| File | OS | Description |
| :--- | :--- | :--- |
| `install.sh` | 🐧 Linux | Interactive installer to generate config and setup systemd. |
| `ntfs_watch_and_repair.sh` | 🐧 Linux | Main logic. Checks mound, modifies Grub, reboots. |
| `ntfs-watch.service` | 🐧 Linux | Systemd service definition. |
| `ntfs-watch.timer` | 🐧 Linux | Systemd timer (default: runs every 20 mins). |
| `tg_send` | 🐧 Linux | Helper script to send logs to Telegram. |
| `chkdisk.bat` | 🪟 Windows | Runs `chkdsk`, fixes Grub, sets reboot flag. |
| `reboot-from-file.bat` | 🪟 Windows | Checks reboot flag and performs the actual reboot. |
| `reboot_to_linux.bat` | 🪟 Windows | **Manual** helper to force a reboot to Linux (not part of automation). |
| `tg_send.bat` | 🪟 Windows | Helper batch file to send logs to Telegram. |

## 💡 Tips & Troubleshooting

### Viewing Windows Logs on Linux
Windows batch files often use legacy encodings (like CP866 for Cyrillic/Russian Windows). To read the logs correctly on Linux, convert them with `iconv`:

```bash
iconv -f CP866 -t UTF-8 /mnt/win/chkdisk.log | less
```

-   Replace `/mnt/win` with your actual Windows mount point.
-   Replace `CP866` with your local Windows encoding if different (e.g., `CP1252` for Western Europe).

## ⚠️ Important Notes

-   **Grub Indices**: The scripts use strict regex to find `set default=...`. They assume a simple toggle: `0` for Windows, `1` for Linux. If your Grub menu has a different order, you **MUST** edit the `sed` command in the Bash script and the PowerShell logic in the Batch file.
-   **Safety**: Always have a backup of your `grub.cfg` before deploying this. The script creates backups (`grub.cfg.bak_TIMESTAMP`), but being safe is better.
-   **Loops**: The scripts have safeguards (e.g., `MAX_ATTEMPTS` in Linux, reboot flags in Windows) to prevent infinite reboot loops if repair fails.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
