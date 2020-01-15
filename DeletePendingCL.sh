#!/bin/bash

echo " "
echo cleaning pending empty changelist

if [ -z "$1" ]
then
	echo list clientspecs on `hostname`
	p4 clients | grep -i `hostname`
	echo " "
	echo choose your client spec
	read P4CLIENTSPEC
else
	P4CLIENTSPEC=$1
fi

echo " "
echo p4 changelists -c $P4CLIENTSPEC -s pending
RESULTS=`p4 changelists -c $P4CLIENTSPEC -s pending`
echo $RESULTS
echo " "

if [ -n "$RESULTS" ]
then
	echo continue \? [yes/no]
	read deleteit
	if [ "$deleteit" = "yes" ]
	then
		p4 changelists -c $P4CLIENTSPEC -s pending | awk '{print $2}' | xargs -i@ -t p4 -c $P4CLIENTSPEC change -d @
	else
		echo no delete
	fi
else
	echo nothing to delete
fi

echo " "
echo END of $0
echo " "
