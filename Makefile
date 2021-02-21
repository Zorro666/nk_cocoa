# Install
BIN = demo

# Flags
CFLAGS += -DGL_SILENCE_DEPRECATION
CFLAGS += $(shell pkg-config --cflags glew)
GLEW := $(shell pkg-config --libs glew)

SRC = main.cpp jake_gl.c jake_gl_cocoa.m
OBJ = $(SRC:.c=.o)

LIBS := $(GLEW) -framework OpenGL -framework Cocoa

$(BIN):
	@mkdir -p bin
	rm -f bin/$(BIN) $(OBJS)
	$(CC) $(SRC) $(CFLAGS) -o bin/$(BIN) $(LIBS)
