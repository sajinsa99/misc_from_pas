#!/bin/sh

for DIR in /net/build-drops-lvb/space1/dropzone /net/build-drops-lv/space5/drop/dropzone
do
echo $DIR
echo $1
	if [ -d $DIR/$1 ]
	then
		cd $DIR/$1
		pwd
		if [ -r makesymlinks.sh ]
		then
			echo sh makesymlinks.sh *_greatest
			sh makesymlinks.sh *_greatest
		fi
	else
		echo $DIR/$1 does not exist
	fi

done
