# User configuration options
GRAPH=examples/blink.fbp
MODEL=uno
AVRMODEL=at90usb1287
MBED_GRAPH=examples/blink-mbed.fbp
LINUX_GRAPH=examples/blink-rpi.fbp
UPLOAD_DIR=/mnt

# SERIALPORT=/dev/somecustom
# ARDUINO=/home/user/Arduino-1.0.5

AVRSIZE=avr-size
AVRGCC=avr-g++
AVROBJCOPY=avr-objcopy
DFUPROGRAMMER=dfu-programmer
VERSION=$(shell git describe --tags)
OSX_ARDUINO_APP=/Applications/Arduino.app
AVR_FCPU=1000000UL

# Not normally customized
CPPFLAGS=-ffunction-sections -fdata-sections -g -Os -w
DEFINES=-DHAVE_DALLAS_TEMPERATURE


INOOPTIONS=--board-model=$(MODEL)

ifdef SERIALPORT
INOUPLOADOPTIONS=--serial-port=$(SERIALPORT)
endif

ifdef ARDUINO
INOOPTIONS+=--arduino-dist=$(ARDUINO)
endif

# Platform specifics
ifeq ($(OS),Windows_NT)
	# TODO, test and fix
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Darwin)
        AVRSIZE=$(OSX_ARDUINO_APP)/Contents/Resources/Java/hardware/tools/avr/bin/avr-size
	AVRGCC=$(OSX_ARDUINO_APP)/Contents/Resources/Java/hardware/tools/avr/bin/avr-g++
	AVROBJCOPY=$(OSX_ARDUINO_APP)/Contents/Resources/Java/hardware/tools/avr/bin/avr-objcopy
    endif
    ifeq ($(UNAME_S),Linux)
        # Nothing needed :D
    endif
endif

# Rules
all: build

build-arduino: install
	mkdir -p build/arduino/src
	mkdir -p build/arduino/lib
	ln -sf `pwd`/microflo build/arduino/lib/
	unzip -q -n ./thirdparty/OneWire.zip -d build/arduino/lib/
	unzip -q -n ./thirdparty/DallasTemperature.zip -d build/arduino/lib/
	cd build/arduino/lib && test -e patched || patch -p0 < ../../../thirdparty/DallasTemperature.patch
	cd build/arduino/lib && test -e patched || patch -p0 < ../../../thirdparty/OneWire.patch
	touch build/arduino/lib/patched
	node microflo.js generate $(GRAPH) build/arduino/src/firmware.cpp arduino
	cd build/arduino && ino build $(INOOPTIONS) --cppflags="$(CPPFLAGS) $(DEFINES)"
	$(AVRSIZE) -A build/arduino/.build/$(MODEL)/firmware.elf

build-avr: install
	mkdir -p build/avr
	node microflo.js generate $(GRAPH) build/avr/firmware.cpp avr
	cd build/avr && $(AVRGCC) -o firmware.elf firmware.cpp -I../../microflo -DF_CPU=$(AVR_FCPU) -DAVR=1 -Wall -Werror -Wno-error=overflow -mmcu=$(AVRMODEL) -fno-exceptions -fno-rtti $(CPPFLAGS)
	cd build/avr && $(AVROBJCOPY) -j .text -j .data -O ihex firmware.elf firmware.hex
	$(AVRSIZE) -A build/avr/firmware.elf

build-mbed: install
	cd thirdparty/mbed && python2 workspace_tools/build.py -t GCC_ARM -m LPC1768
	rm -rf build/mbed
	mkdir -p build/mbed
	node microflo.js generate $(MBED_GRAPH) build/mbed/main.cpp mbed
	cp Makefile.mbed build/mbed/Makefile
	cd build/mbed && make ROOT_DIR=./../../

build-linux: install
	rm -rf build/linux
	mkdir -p build/linux
	node microflo.js generate $(LINUX_GRAPH) build/linux/main.cpp linux
	cd build/linux && g++ -o firmware main.cpp -std=c++0x -I../../microflo -DLINUX -Wall -Werror -lrt

build-emscripten: install
	rm -rf build/emscripten
	mkdir -p build/emscripten
	node microflo.js generate $(LINUX_GRAPH) build/emscripten/main.cpp linux
	cd build/emscripten && emcc -o firmware.js main.cpp -I../../microflo -Wall -Werror

build: build-arduino build-avr

upload: build-arduino
	cd build/arduino && ino upload $(INOUPLOADOPTIONS) $(INOOPTIONS)

upload-dfu: build-avr
	cd build/avr && sudo $(DFUPROGRAMMER) $(AVRMODEL) erase
	sleep 1
	cd build/avr && sudo $(DFUPROGRAMMER) $(AVRMODEL) flash firmware.hex || sudo $(DFUPROGRAMMER) $(AVRMODEL) flash firmware.hex || sudo $(DFUPROGRAMMER) $(AVRMODEL) flash firmware.hex || sudo $(DFUPROGRAMMER) $(AVRMODEL) flash firmware.hex || sudo $(DFUPROGRAMMER) $(AVRMODEL) flash firmware.hex
	sudo $(DFUPROGRAMMER) $(AVRMODEL) start

upload-mbed: build-mbed
	cd build/mbed && sudo cp firmware.bin $(UPLOAD_DIR)

clean:
	git clean -dfx --exclude=node_modules

install:
	npm install

release-arduino:
	rm -rf build/microflo-arduino
	mkdir -p build/microflo-arduino/microflo/examples/Standalone
	cp -r microflo build/microflo-arduino/
	cp build/arduino/src/firmware.cpp build/microflo-arduino/microflo/examples/Standalone/Standalone.pde
	cd build/microflo-arduino && zip -q -r ../microflo-arduino.zip microflo

release-ui:
	rm -rf build/noflo-ui
	cd thirdparty/noflo-ui && git checkout-index -f -a --prefix=../../build/noflo-ui/
	cd build/noflo-ui && npm install && npm install grunt-cli
	cd build/noflo-ui && ./node_modules/.bin/grunt build
	rm -r build/noflo-ui/node_modules

release-microflo:
	rm -rf build/microflo
	git checkout-index -f -a --prefix=build/microflo/
	mkdir -p build/microflo/node_modules
	cd build/microflo && npm install ../../thirdparty/node-serialport && npm install
	cp -r thirdparty/node-serialport/build/Release/Darwin build/microflo/node_modules/serialport/build/Release
	cp -r thirdparty/node-serialport/build/Release/Windows_NT build/microflo/node_modules/serialport/build/Release

release-mbed: build-mbed
    # TODO: package into something usable with MBed tools

release-linux: build-linux
    # TODO: package?

release-emscripten: build-emscripten
    # TODO: package?

release: install build release-mbed release-linux release-emscripten release-microflo release-arduino release-ui
	rm -rf build/microflo-$(VERSION)
	mkdir -p build/microflo-$(VERSION)
	cp -r build/microflo-arduino.zip build/microflo-$(VERSION)/
	cp -r build/noflo-ui build/microflo-$(VERSION)/
	cp -r build/microflo build/microflo-$(VERSION)/
	cd build && zip -q --symlinks -r microflo-$(VERSION).zip microflo-$(VERSION)

check-release: release
	rm -rf build/check-release
	mkdir -p build/check-release
	cd build/check-release && unzip -q ../microflo-$(VERSION)
	cd build/check-release/microflo-$(VERSION)/microflo && npm test

.PHONY: all build install clean release release-microflo release-arduino release-ui check-release

