#!/bin/bash
# gitpull.sh - HOLFY27 Manager Root Git Pull Script
# Version 1.0 - January 2026
# Author - Burke Azbill and HOL Core Team
# Executed by root cron at boot to pull Core Team repository updates

# Source environment
. /root/.bashrc

LOGFILE="/tmp/gitpull-root.log"
HOLROOT="/root/hol"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> ${LOGFILE}
}

log_message "Starting root gitpull.sh"

# Wait for network/proxy to be available
wait_for_proxy() {
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --max-time 5 -x http://proxy.site-a.vcf.lab:3128 https://github.com > /dev/null 2>&1; then
            log_message "Proxy is available"
            return 0
        fi
        log_message "Waiting for proxy (attempt ${attempt}/${max_attempts})..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    log_message "WARNING: Proxy not available after ${max_attempts} attempts"
    return 1
}

# Perform git pull
do_git_pull() {
    cd "${HOLROOT}" || exit 1
    
    # Determine branch
    cloud=$(/usr/bin/vmtoolsd --cmd 'info-get guestinfo.ovfEnv' 2>&1)
    holdev=$(echo "${cloud}" | grep -i hol-dev)
    
    if [ "${cloud}" = "No value found" ] || [ -n "${holdev}" ]; then
        branch="dev"
    else
        branch="main"
    fi
    
    log_message "Using branch: ${branch}"
    
    # Stash local changes in production
    if [ "${branch}" = "main" ]; then
        log_message "Stashing local changes for production"
        git stash >> ${LOGFILE} 2>&1
    fi
    
    # Perform pull
    git checkout ${branch} >> ${LOGFILE} 2>&1
    git pull origin ${branch} >> ${LOGFILE} 2>&1
    
    if [ $? -eq 0 ]; then
        log_message "Git pull successful"
    else
        log_message "Git pull failed - continuing with existing code"
    fi
}

# Make sure additional required tools are present in the environment
if ! command -v tdns-mgr &> /dev/null; then
    log_message "tdns-mgr could not be found - installing..."
    # download https://raw.githubusercontent.com/burkeazbill/tdns-mgr/refs/heads/main/tdns-mgr.sh as /usr/bin/tdns-mgr
    curl -o /usr/bin/tdns-mgr https://raw.githubusercontent.com/burkeazbill/tdns-mgr/refs/heads/main/tdns-mgr.sh
    chmod 755 /usr/bin/tdns-mgr
    /usr/bin/tdns-mgr completion bash | sudo tee /etc/bash_completion.d/tdns-mgr > /dev/null
    mkdir -p /root/.config/tdns-mgr
    log_message "tdns-mgr installed and command completion enabled"
else
    log_message "tdns-mgr already installed"
fi

# Make sure the tdns-mgr config file is present
if [ ! -f /root/.config/tdns-mgr/.tdns-mgr.conf ]; then
    log_message "tdns-mgr config file not found - creating..."
    # create a default config file
    cat > /root/.config/tdns-mgr/.tdns-mgr.conf <<EOF
# Environment variables for tdns-mgr.sh
DNS_SERVER=10.1.10.129
DNS_PORT=5380
DNS_PROTOCOL=http
DNS_TOKEN=
DNS_USER=admin
DNS_PASS=
EOF
    log_message "tdns-mgr config file created"
fi

cat /home/holuser/creds.txt | tdns-mgr login

# Install oh-my-posh
if ! command -v oh-my-posh &> /dev/null; then
    log_message "oh-my-posh could not be found - installing..."
    curl -s https://ohmyposh.dev/install.sh | bash -s -- -d /usr/bin
    chmod 755 /usr/bin/oh-my-posh
    mkdir -p /root/.config/ohmyposh
    log_message "oh-my-posh installed"
else
    log_message "oh-my-posh already installed"
fi

# Make sure the oh-my-posh config file is present
if [ ! -f /root/.config/ohmyposh/holoconsole.omp.json ]; then
    log_message "oh-my-posh config file not found - creating..."
    # Retrieve the config file from https://raw.githubusercontent.com/burkeazbill/DimensionQuestDotFiles/refs/heads/main/.config/ohmyposh/holoconsole.omp.json
    curl -s https://raw.githubusercontent.com/burkeazbill/DimensionQuestDotFiles/refs/heads/main/.config/ohmyposh/holoconsole.omp.json > /root/.config/ohmyposh/holoconsole.omp.json
     # Add the following code block to the end of the /home/holuser/.bashrc file
    echo 'if [ -f ~/.config/ohmyposh/holoconsole.omp.json ]; then
        if [[ -n "$SSH_TTY" ]]; then
            eval "$(oh-my-posh init bash --config ~/.config/ohmyposh/holoconsole.omp.json)"
        fi
    fi' >> /root/.bashrc
    log_message "oh-my-posh config file created"
EOF
    log_message "oh-my-posh config file created"
fi

# Make sure the oh-my-posh config file is present for holuser
if [ ! -f /home/holuser/.config/ohmyposh/holoconsole.omp.json ]; then
    log_message "oh-my-posh config file for holuser not found - creating..."
    # Retrieve the config file from https://raw.githubusercontent.com/burkeazbill/DimensionQuestDotFiles/refs/heads/main/.config/ohmyposh/holoconsole.omp.json
    cp /root/.config/ohmyposh/holoconsole.omp.json /home/holuser/.config/ohmyposh/holoconsole.omp.json
    chown holuser:holuser -R /home/holuser/.config
    # Add the following code block to the end of the /home/holuser/.bashrc file
    echo 'if [ -f ~/.config/ohmyposh/holoconsole.omp.json ]; then
        if [[ -n "$SSH_TTY" ]]; then
            eval "$(oh-my-posh init bash --config ~/.config/ohmyposh/holoconsole.omp.json)"
        fi
    fi' >> /home/holuser/.bashrc
    log_message "oh-my-posh config file created for holuser"
fi

# Wait for proxy before git operations
wait_for_proxy

# Perform git pull
if [ -d "${HOLROOT}/.git" ]; then
    do_git_pull
else
    log_message "No git repository found at ${HOLROOT}"
fi

log_message "Root gitpull.sh completed"
