DEMO = demo
SIMPLE = simple
#
# Flags
CFLAGS += -DGL_SILENCE_DEPRECATION
CFLAGS += $(shell pkg-config --cflags glew)
GLEW := $(shell pkg-config --libs glew)

SRC = jake_gl.c jake_gl_cocoa.m

LIBS := $(GLEW) -framework OpenGL -framework Cocoa

all: demo simple

demo:
	@mkdir -p bin
	rm -f demo *.o
	$(CC) demo.cpp $(SRC) $(CFLAGS) -o demo $(LIBS)

simple:
	@mkdir -p bin
	rm -f simple *.o
	$(CC) simple.cpp $(SRC) $(CFLAGS) -o simple $(LIBS)
