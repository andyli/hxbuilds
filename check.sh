#!/bin/sh
EXITVAR=0

BASE=$PWD
for proj in projects/*; do
	cd $BASE
	echo $proj
	if [ -d "${proj}" ]; then
		echo "Checking $(basename $proj)"
		cd "${proj}"
		./check.sh || EXITVAR=1

		REV=$(./getrev.sh)
		VER=$(./getver.sh)
		PROJECT=$(basename $proj)
		PROJEXITVAR=0
		for plat in installed-platforms/*; do
			if [ -f repo/.updated ] && [ -d "${plat}" ]; then
				echo "Building $PROJECT for $(basename $plat)"
				if [ -f repo/.force ]; then
					rm -rf "$BASE/$proj/$plat/build"
				fi
				cd "$BASE/$proj/$plat"
			
				if [ ! -f "build/.r$REV" ] && [ ! -f "out/${PROJECT}_r$REV.tar.gz" ]; then
					rm -rf build
					mkdir build
					./build.sh "$REV" "$VER" && touch "build/.r$REV" || PROJEXITVAR=1
				fi
				if [ -f "build/.r$REV" ]; then
					rm -rf "$PROJECT-$VER"
					cp -Rf build "$PROJECT-$VER"
					rm -f "$PROJECT-$VER/.r$REV"
					tar -zcvf "out/${PROJECT}_r$REV.tar.gz" "$PROJECT-$VER"
					rm -rf "$PROJECT-$VER"
				else
					PROJEXITVAR=1
				fi

				if [ -f "out/${PROJECT}_r$REV.tar.gz" ]; then
					cd ../../../..
					./sync.sh "$BASE/$proj/${plat}/out/${PROJECT}_r$REV.tar.gz" "$(basename $proj)/$(basename ${plat})/${PROJECT}_$(date -u +'%Y-%m-%d')_$REV.tar.gz" || EXITVAR=1
					./sync.sh "$BASE/$proj/${plat}/out/${PROJECT}_r$REV.tar.gz" "$(basename $proj)/$(basename ${plat})/${PROJECT}_latest.tar.gz" || EXITVAR=1
					echo "neko $BASE/testrunner/bin/runner.n run-project $BASE/$proj $PROJECT $REV"
					neko $BASE/testrunner/bin/runner.n run-project $BASE/$proj $PROJECT "$REV"
				else
					PROJEXITVAR=1
				fi
			fi
			cd $BASE/$proj
		done

		if [ $PROJEXITVAR = 0 ]; then
			if [ -f repo/.updated ]; then
				echo "removing updated"
				rm repo/.updated
				rm -f repo/.force
			fi
		else
			EXITVAR=1
		fi
	fi
done

exit $EXITVAR
