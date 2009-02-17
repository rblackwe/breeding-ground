#!/usr/bin/bash
mkdir /tmp/hardcopygrep
screen -X chdir /tmp/hardcopygrep
myvar=0
while [ $myvar -ne 40 ]
do
	screen -X at $myvar hardcopy
	myvar=$(( $myvar + 1))
done

find /tmp/hardcopygrep | xargs grep -n $1

