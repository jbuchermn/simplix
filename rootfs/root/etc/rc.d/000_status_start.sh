#!/bin/sh
if [ ! -z "$SIMPLIX_STATUS_GPIO" ]; then
	mkdir -p /var/run/simplix-status
	simplix-status -d -f /var/run/simplix-status $SIMPLIX_STATUS_GPIO
	echo "fast" > /var/run/simplix-status
fi
