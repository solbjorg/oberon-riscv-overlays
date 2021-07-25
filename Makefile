CFLAGS = -g -O2 -flto -Wall -Wextra -Wconversion -Wno-sign-conversion -Wno-unused-parameter -std=c99

norebo: Runtime/norebo.c Runtime/risc-cpu.c Runtime/risc-cpu.h
	$(CC) -o $@ Runtime/norebo.c Runtime/risc-cpu.c $(CFLAGS)
	./build.sh

imagerv: norebo
	make clean; make
	./build-image.py -r OberonRV/Oberon -m manifests/manifest.csv

imager5: norebo
	make clean; make
	./build-image.py upstream -m manifests/manifest_oberon2013.csv

clean:
	rm -f norebo
	rm -rf build imagebuild
