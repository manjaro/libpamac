#! /bin/sh

for i in `ls ./ | sed s'|.po||'` ; do
	msgmerge --update --no-wrap --add-location=file --backup=none ./$i.po pamac.pot
done
