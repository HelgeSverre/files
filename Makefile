BIN := bin/files
SRC := files.nim

build:
	mkdir -p bin
	nim c -d:release --opt:speed -o:$(BIN) $(SRC)

run: build
	./$(BIN) .

test:
	nim c -r --hints:off --path:. tests/test_ignore.nim

install: build
	mkdir -p $(HOME)/.local/bin
	cp $(BIN) $(HOME)/.local/bin/files

clean:
	rm -rf bin nimcache

.PHONY: build run test install clean
