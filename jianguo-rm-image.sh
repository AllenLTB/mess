#!/bin/bash

grep '.assets/ima' ./*.md | sed -r 's#.*assets/(.*png).*#\1#g' > imagerm1.txt
ls -l .assets/ | grep image | awk '{print $NF}' > imagerm2.txt

for i in `cat imagerm1.txt` ; do
	sed -i "/$i/d" imagerm2.txt
done
