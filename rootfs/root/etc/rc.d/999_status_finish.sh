#!/bin/sh
if [ -e "/var/run/simplix-status" ]; then
	echo "slow" > /var/run/simplix-status
fi
