#!/bin/bash
# mount.sh - HOLFY27 Manager Root Mount Script
# Version 1.0 - January 2026
# Author - Burke Azbill and HOL Core Team
# Enhanced with NFS server for holorouter communication
#==============================================================================
# CONFIGURATION VARIABLES
#==============================================================================

# Retry and timeout configuration (can be overridden by environment variables)
MAX_PING_ATTEMPTS=${MAX_PING_ATTEMPTS:-30}
PING_RETRY_DELAY=${PING_RETRY_DELAY:-2}
maincon="console"
LMC=false

# File paths
configini="/tmp/config.ini"
lmcbookmarks="holuser@${maincon}:/home/holuser/.config/gtk-3.0/bookmarks"
MOUNT_FAILURE_FILE=${MOUNT_FAILURE_FILE:-"/tmp/.mountfailed"}
HOLOROUTER_DIR="/tmp/holorouter"

# Get password from creds.txt
password=$(cat /home/holuser/creds.txt)

#==============================================================================
# FUNCTIONS
#==============================================================================

# Logging function with timestamp
log_message() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1"
}

# Create mount failure marker file
mark_mount_failed() {
    local reason=$1
    log_message "CRITICAL: Mount operation failed - ${reason}"
    cat > "${MOUNT_FAILURE_FILE}" <<EOF
Mount Failed: ${reason}
Timestamp: $(date)
Console: ${maincon}
LMC Mode: ${LMC}
Script: $0
EOF
    chmod 644 "${MOUNT_FAILURE_FILE}"
}

# Generic retry function with timeout
# Usage: retry_with_timeout <max_attempts> <delay> <description> <command>
retry_with_timeout() {
    local max_attempts=$1
    local delay=$2
    local description=$3
    shift 3
    local command="$4"
    local attempt=1
    
    log_message "Starting: ${description} (max attempts: ${max_attempts})"
    
    while [ $attempt -le "$max_attempts" ]; do
        log_message "Attempt ${attempt}/${max_attempts}: ${description}"
        
        if eval "$command"; then
            log_message "SUCCESS: ${description}"
            return 0
        fi
        
        if [ $attempt -lt "$max_attempts" ]; then
            log_message "FAILED: ${description}. Retrying in ${delay} seconds..."
            sleep "$delay"
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_message "ERROR: ${description} failed after ${max_attempts} attempts"
    return 1
}

clear_mount() {
    # make sure we have clean mount points
    if ! mount | grep -q "${1}"; then   # mount point is not mounted
        log_message "Clearing ${1}..."
        rm -rf "${1}" > /dev/null 2>&1
        mkdir "${1}"
        chown holuser:holuser "${1}"
        chmod 775 "${1}"
    fi
}

secure_holuser() {
    # update the holuser sudoers for installations on the manager
    [ -f /root/holdoers ] && cp -p /root/holdoers /etc/sudoers.d/holdoers
    # change permissions so non-privileged installs are allowed
    chmod 666 /var/lib/dpkg/lock-frontend
    chmod 666 /var/lib/dpkg/lock
    if [ "${vlp_cloud}" != "NOT REPORTED" ]; then
        log_message "PRODUCTION - SECURING HOLUSER."
        cat ~root/test2.txt | mcrypt -d -k bca -q > ~root/clear.txt
        pw=$(cat ~root/clear.txt)
        passwd holuser <<END
$pw
$pw
END
        rm -f ~root/clear.txt
        if [ -f ~holuser/.ssh/authorized_keys ]; then
            mv ~holuser/.ssh/authorized_keys ~holuser/.ssh/unauthorized_keys
        fi
        # secure the router (via NFS now, but still set password)
        # Router will read password from mounted files if needed
    else
        log_message "NORMAL HOLUSER."
        passwd holuser <<END
$password
$password
END
        if [ -f ~holuser/.ssh/unauthorized_keys ]; then
            mv ~holuser/.ssh/unauthorized_keys ~holuser/.ssh/authorized_keys
        fi
    fi
}

setup_nfs_server() {
    log_message "Setting up NFS server for holorouter communication..."
    
    # Create the holorouter communication directory
    mkdir -p "${HOLOROUTER_DIR}"
    chown holuser:holuser "${HOLOROUTER_DIR}"
    chmod 775 "${HOLOROUTER_DIR}"
    
    # Install NFS server if not present
    if ! dpkg -l | grep -q nfs-kernel-server; then
        log_message "Installing nfs-kernel-server..."
        apt-get update -qq
        apt-get install -y nfs-kernel-server > /dev/null 2>&1
    fi
    
    # Configure NFS exports
    EXPORT_LINE="${HOLOROUTER_DIR} 10.1.10.129(rw,sync,no_subtree_check,no_root_squash)"
    
    if ! grep -q "${HOLOROUTER_DIR}" /etc/exports 2>/dev/null; then
        log_message "Adding NFS export for ${HOLOROUTER_DIR}..."
        echo "${EXPORT_LINE}" >> /etc/exports
    fi
    
    # Reload exports and restart NFS server
    exportfs -ra
    systemctl enable --now nfs-kernel-server
    systemctl restart nfs-kernel-server
    exportfs -v
    log_message "NFS server configured. Exporting ${HOLOROUTER_DIR} to 10.1.10.129"
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

# Ensure log file is readable by all (cron redirects output here)
chmod 666 /tmp/mount.log 2>/dev/null || true

# Ensure clean state
rm -f "${MOUNT_FAILURE_FILE}"
clear_mount /lmchol
clear_mount /vpodrepo

# Setup NFS server for holorouter
setup_nfs_server

########## Begin /vpodrepo mount handling ##########
# check for /vpodrepo mount and prepare volume if possible
if mount | grep -q /vpodrepo; then # mount is there now is the volume ready
    if [ -d /vpodrepo/lost+found ]; then
        log_message "/vpodrepo volume is ready."
    fi
else
    log_message "/vpodrepo mount is missing."
    # attempt to mount /dev/sdb1
    if [ -b /dev/sdb1 ]; then
        log_message "/dev/sdb1 is a block device file. Attempting to mount /vpodrepo..."
        if mount /dev/sdb1 /vpodrepo; then
            log_message "Successful mount of /vpodrepo."
            chown -R holuser:holuser /vpodrepo/* > /dev/null 2>&1
        fi
    else # now the tricky part - need to prepare the drive
        log_message "Preparing new volume..."
        if [ -b /dev/sdb ] && [ ! -b /dev/sdb1 ]; then
            log_message "Creating new partition on external volume /dev/sdb."
            /usr/sbin/fdisk /dev/sdb <<END
n
p
1


w
quit
END
            sleep 1 # adding a sleep to let fdisk save the changes
            if [ -b /dev/sdb1 ]; then
                log_message "Creating file system on /dev/sdb1"
                /usr/sbin/mke2fs -t ext4 /dev/sdb1
                log_message "Mounting /vpodrepo"
                mount /dev/sdb1 /vpodrepo
                chown holuser:holuser /vpodrepo
                chmod 775 /vpodrepo
            fi
        fi
    fi
    if [ -f /vpodrepo/lost+found ]; then
        log_message "/vpodrepo mount is successful."
    fi
fi
########## End /vpodrepo mount handling ##########

########## Begin console connectivity check ##########
# Wait for console to be reachable
if ! retry_with_timeout "${MAX_PING_ATTEMPTS}" "${PING_RETRY_DELAY}" \
    "Ping console ${maincon}" \
    "ping -c 4 ${maincon} > /dev/null 2>&1"; then
    mark_mount_failed "Console ${maincon} not reachable after ${MAX_PING_ATTEMPTS} attempts"
    exit 1
fi
########## End console connectivity check ##########

########## Begin console Type check and Mount ##########
log_message "Checking for LMC at ${maincon}:2049..."
# Loop for 6 total attempts (1 initial + 5 retries)
for i in {1..6}; do
    # Correctly check the exit code of nc
    if nc -z "${maincon}" 2049; then
        log_message "LMC detected (Attempt $i/6). Performing NFS mount..."
        while [ ! -d /lmchol/home/holuser/desktop-hol ]; do
            log_message "Mounting / on the LMC to /lmchol..."
            mount -t nfs -o soft,timeo=50,retrans=5,_netdev ${maincon}:/ /lmchol
            sleep 20
        done
        LMC=true
        break # Exit the loop on success
    fi

    # If this was the last attempt, don't sleep
    if [ "$i" -eq 6 ]; then
        break
    fi

    log_message "Attempt $i/6 failed. Retrying in 10 seconds..."
    sleep 20
done

# Only check for WMC if LMC not detected - WMC REMOVED in HOLFY27
if [ "$LMC" = false ]; then
    log_message "LMC not detected. HOLFY27 requires Linux Main Console."
    mark_mount_failed "LMC (port 2049) not detected on ${maincon}. WMC is not supported."
    mkdir -p /lmchol/hol
    echo "Fail to mount console... aborting labstartup..." > /lmchol/hol/startup_status.txt
    exit 1
fi

########## End console Type check and Mount ##########

# the holuser account copies the config.ini to /tmp from 
# either the mainconsole (must wait for the mount)
# or from the vpodrepo
while [ ! -f "$configini" ]; do
    log_message "Waiting for ${configini}..."
    sleep 3
done

# retrieve the cloud org from the vApp Guest Properties (is this prod or dev?)
cloudinfo="/tmp/cloudinfo.txt"
vlp_cloud="NOT REPORTED"
while [ "${vlp_cloud}" = "NOT REPORTED" ]; do
    sleep 30
    if [ -f "$cloudinfo" ]; then
        vlp_cloud=$(cat $cloudinfo)
        log_message "vlp_cloud: $vlp_cloud"
        break
    fi
    log_message "Waiting for ${cloudinfo}..."
done

secure_holuser

# LMC-specific actions
sshoptions='-o StrictHostKeyChecking=accept-new'
if [ "$LMC" = true ]; then
    # remove the manager bookmark from nautilus
    if [ "${vlp_cloud}" != "NOT REPORTED" ]; then
        log_message "Removing manager bookmark from Nautilus."
        sshpass -p "${password}" scp "${sshoptions}" ${lmcbookmarks} /root/bookmarks.orig
        grep -vi manager /root/bookmarks.orig > /root/bookmarks
        sshpass -p "${password}" scp "${sshoptions}" /root/bookmarks ${lmcbookmarks}
    else
        log_message "Not removing manager bookmark from Nautilus."
    fi
fi

log_message "mount.sh completed successfully."
