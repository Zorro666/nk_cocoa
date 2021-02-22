DEMO = demo
SIMPLE = simple

# Flags
CFLAGS += -DGL_SILENCE_DEPRECATION
CFLAGS += $(shell pkg-config --cflags glew)

SRC = jake_gl.c jake_gl_cocoa.m
HEADERS = jake_gl.h jake_gl_internal.h

LIBS := -framework OpenGL -framework Cocoa

all: demo simple

clean:
	@rm -f demo *.o
	@rm -f simple *.o

demo: demo.cpp $(SRC) $(HEADERS)
	$(CC) demo.cpp $(SRC) $(CFLAGS) -o demo $(LIBS)

simple: simple.cpp $(SRC) $(HEADERS)
	$(CC) simple.cpp $(SRC) $(CFLAGS) -o simple $(LIBS)
