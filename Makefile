.PHONY: all build release test app install clean

all: build

build:
	swift build

release:
	swift build -c release

test:
	swift test

app:
	./scripts/build_app.sh

install:
	./scripts/build_app.sh --install

clean:
	swift package clean
	rm -rf dist .build
