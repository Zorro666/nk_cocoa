TARGETS += demo
TARGETS += simple
TARGETS += checkerboard

# Flags
CFLAGS += -DGL_SILENCE_DEPRECATION
CFLAGS += $(shell pkg-config --cflags glew)
CFLAGS += -target arm64-apple-macos11

SRC = apple_cocoa.m
HEADERS = apple_cocoa.h

LIBS := -framework OpenGL -framework Cocoa -framework Quartz

all: $(TARGETS)

clean:
	@rm -f $(TARGETS) *.o

demo: demo.cpp $(SRC) $(HEADERS)
	$(CC) $@.cpp $(SRC) $(CFLAGS) -o $@ $(LIBS)

simple: simple.cpp $(SRC) $(HEADERS)
	$(CC) $@.cpp $(SRC) $(CFLAGS) -o $@ $(LIBS)

checkerboard: checkerboard.cpp $(SRC) $(HEADERS)
	$(CC) $@.cpp $(SRC) $(CFLAGS) -o $@ $(LIBS)
