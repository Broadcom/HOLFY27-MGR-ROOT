#!/bin/bash
# prepLMC.sh - HOLFY27 Manager Root Prep LMC Script
# Version 1.0 - January 2026
# Author - Burke Azbill and HOL Core Team
# Prepares vm for milestone capture

# Source environment
. /root/.bashrc

# empty the trash (happens at logout but need to clear dirty bloks
rm -rf /home/holuser/.local/share/Trash/*

# remove temporary files to clear dirty blocks (don't force)
rm -r /tmp/*

# delete the known_host files that cause issues
echo "Removing known_hosts files..."
rm /home/holuser/.ssh/known_hosts
rm /root/.ssh/known_hosts

# delete the PuTTY hostkeys
echo "Removing PuTTY hostkey files..."
rm /home/holuser/.putty/hostkeys

# clear dirty blocks
echo "Clearing dirty blocks..."
dd if=/dev/zero of=/tmp/zeros.txt ; rm -f /tmp/zeros.txt
