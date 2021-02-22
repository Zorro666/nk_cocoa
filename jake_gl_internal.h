#pragma once

#include "jake_gl.h"

#include <Carbon/Carbon.h>

typedef int GLFWbool;

typedef struct _JATGLwindow_config   _JATGLwindow_config;
typedef struct _JATGLcontext     _JATGLcontext;
typedef struct _JATGLwindow      _JATGLwindow;
typedef struct _JATGLmodule     _JATGLmodule;
typedef struct _JATGL_TLS         _JATGL_TLS;

typedef void (* _GLFWmakecontextcurrentfun)(_JATGLwindow*);
typedef void (* _GLFWswapbuffersfun)(_JATGLwindow*);
typedef JATGLglproc (* _GLFWgetprocaddressfun)(const char*);
typedef void (* _GLFWdestroycontextfun)(_JATGLwindow*);

#define GL_COLOR_BUFFER_BIT 0x00004000

typedef int GLint;
typedef unsigned int GLuint;
typedef unsigned int GLenum;
typedef unsigned int GLbitfield;
typedef unsigned char GLubyte;

typedef void (* PFNGLCLEARPROC)(GLbitfield);
typedef const GLubyte* (* PFNGLGETSTRINGPROC)(GLenum);
typedef void (* PFNGLGETINTEGERVPROC)(GLenum,GLint*);
typedef const GLubyte* (* PFNGLGETSTRINGIPROC)(GLenum,GLuint);

#ifndef GL_SILENCE_DEPRECATION
#define GL_SILENCE_DEPRECATION
#endif // #ifndef GL_SILENCE_DEPRECATION

#if defined(__OBJC__)
#import <Cocoa/Cocoa.h>
#else
typedef void* id;
#endif

typedef TISInputSourceRef (*PFN_TISCopyCurrentKeyboardLayoutInputSource)(void);
typedef void* (*PFN_TISGetInputSourceProperty)(TISInputSourceRef,CFStringRef);
typedef UInt8 (*PFN_LMGetKbdType)(void);

typedef struct _JATGLwindowNS
{
    id              object;
    id              delegate;
    id              view;
    id              layer;

    int             width, height;
    int             fbWidth, fbHeight;
} _JATGLwindowNS;

typedef struct _JATGLmoduleNS
{
    CGEventSourceRef    eventSource;
    id                  delegate;
    TISInputSourceRef   inputSource;
    id                  unicodeData;
    id                  helper;
    id                  keyUpMonitor;
    id                  nibObjects;

    char                keynames[JATGL_KEY_LAST + 1][17];
    short int           keycodes[256];
    short int           scancodes[JATGL_KEY_LAST + 1];

    struct {
        CFBundleRef     bundle;
        PFN_TISCopyCurrentKeyboardLayoutInputSource CopyCurrentKeyboardLayoutInputSource;
        PFN_TISGetInputSourceProperty GetInputSourceProperty;
        PFN_LMGetKbdType GetKbdType;
        CFStringRef     kPropertyUnicodeKeyLayoutData;
    } tis;

} _JATGLmoduleNS;

struct _JATGLwindow_config
{
    int           width;
    int           height;
    const char*   title;
};

struct _JATGLcontext
{
    PFNGLGETSTRINGIPROC  GetStringi;
    PFNGLGETINTEGERVPROC GetIntegerv;
    PFNGLGETSTRINGPROC   GetString;

    _GLFWmakecontextcurrentfun  makeCurrent;
    _GLFWswapbuffersfun         swapBuffers;
    _GLFWgetprocaddressfun      getProcAddress;
    _GLFWdestroycontextfun      destroy;

    id                pixelFormat;
    id                object;
};

struct _JATGLwindow
{
    struct _JATGLwindow* next;

    GLFWbool            shouldClose;

    char                mouseButtons[3];
    char                keys[JATGL_KEY_LAST + 1];
    double              virtualCursorPosX, virtualCursorPosY;

    _JATGLcontext        context;

    struct {
        JATGLmouse_button_function        mouseButton;
        JATGLcharacter_function               character;
    } callbacks;

    _JATGLwindowNS  ns;
};

struct _JATGL_TLS
{
    GLFWbool        allocated;
    pthread_key_t   key;
};

struct _JATGLmodule
{
    GLFWbool            initialized;
    _JATGLwindow*        windowListHead;
    _JATGL_TLS            contextSlot;

    struct {
        uint64_t        offset;
        uint64_t        frequency;
    } timer;

    _JATGLmoduleNS ns;
    CFBundleRef     framework;
};

extern _JATGLmodule _JATGL;

int _JATGLPlatformInit(void);
void _JATGLPlatformTerminate(void);
void _JATGLPlatformGetCursorPos(_JATGLwindow* window, double* xpos, double* ypos);
const char* _JATGLPlatformGetScancodeName(int scancode);

int _JATGLPlatformCreateWindow(_JATGLwindow* window, const _JATGLwindow_config* wndconfig);
void _JATGLPlatformDestroyWindow(_JATGLwindow* window);
void _JATGLPlatformGetWindowSize(_JATGLwindow* window, int* width, int* height);
void _JATGLPlatformGetFramebufferSize(_JATGLwindow* window, int* width, int* height);

void _JATGLPlatformPollEvents(void);

void _JATGLInputKey(_JATGLwindow* window, int key, int scancode, int action);
void _JATGLInputChar(_JATGLwindow* window, unsigned int codepoint, int mods, GLFWbool plain);
void _JATGLInputMouseClick(_JATGLwindow* window, int button, int action);
void _JATGLInputCursorPos(_JATGLwindow* window, double xpos, double ypos);

