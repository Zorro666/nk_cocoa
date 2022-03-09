TARGETS += demo
TARGETS += simple
TARGETS += checkerboard
TARGETS += metaltriangle

# Flags
#CFLAGS += -DGL_SILENCE_DEPRECATION -mmacosx-version-min=10.15 -arch x86_64
#CFLAGS += -DGL_SILENCE_DEPRECATION -mmacosx-version-min=12.00 -arch arm64
CFLAGS += -DGL_SILENCE_DEPRECATION 
CXXFLAGS += -DGL_SILENCE_DEPRECATION 
CXXFLAGS += -std=c++17

SRC = apple_cocoa.m
HEADERS = apple_cocoa.h

LIBS := -framework Cocoa -framework Quartz
GLLIBS := -framework OpenGL
METALLIBS := -framework Metal

METALTRIANGLE_SRCS_CPP := MetalDraw.cpp metaltriangle.cpp
METALTRIANGLE_SRCS_OBJC := apple_cocoa.m
HEADERS += MetalDraw.h

METALTRIANGLE_SRCS_CPP += metal/official/metal-cpp.cpp
HEADERS += metal/official/metal-cpp.h

METALTRIANGLE_OBJS := $(METALTRIANGLE_SRCS_CPP:.cpp=.o)
METALTRIANGLE_OBJS += $(METALTRIANGLE_SRCS_OBJC:.m=.o)

all: $(TARGETS)

clean:
	@rm -f $(TARGETS) *.o

demo: demo.cpp $(SRC) $(HEADERS)
	$(CC) $@.cpp $(SRC) $(CFLAGS) -o $@ $(LIBS) $(GLLIBS)

simple: simple.cpp $(SRC) $(HEADERS)
	$(CC) $@.cpp $(SRC) $(CFLAGS) -o $@ $(LIBS) $(GLLIBS)

checkerboard: checkerboard.cpp $(SRC) $(HEADERS)
	$(CC) $@.cpp $(SRC) $(CFLAGS) -o $@ $(LIBS) $(GLLIBS)

metaltriangle: $(METALTRIANGLE_OBJS)
	$(CC) -o $@ $^ $(LIBS) $(METALLIBS) -lstdc++

