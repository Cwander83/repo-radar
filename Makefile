.PHONY: all build test clean

all: build

build:
	swift build

test:
	swift test

clean:
	swift package clean
	rm -rf .build
