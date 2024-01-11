#!/bin/sh
[ -e "/etc/secrets/authorized_keys" ] && cat /etc/secrets/authorized_keys >> /home/.ssh/authorized_keys
rm -f /etc/secrets/authorized_keys

if [ ! -e "/etc/ssh/ssh_host_rsa_key" ]; then
    echo "Generating SSH key..."
    ssh-keygen -A
fi
$(which sshd)
