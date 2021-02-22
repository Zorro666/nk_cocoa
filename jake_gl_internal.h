#ifndef __JAKE_GL_INTERNAL_H
#define __JAKE_GL_INTERNAL_H

#include "jake_gl.h"

#include <Carbon/Carbon.h>

typedef struct _JATGLwindow      _JATGLwindow;
typedef struct _JATGLmodule     _JATGLmodule;
typedef struct _JATGL_TLS         _JATGL_TLS;

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

struct _JATGLwindow
{
    _JATGLwindow* next;
    id pixelFormat;
    id object;
    _JATGLwindowNS  ns;
    double virtualCursorPosX, virtualCursorPosY;

    int shouldClose;
    char mouseButtons[3];
    char keys[JATGL_KEY_LAST + 1];

    JATGLMouseButtonCallback mouseButtonCallback;
    JATGLCharacterCallback characterCallback;
};

struct _JATGL_TLS
{
    pthread_key_t key;
    int allocated;
};

struct _JATGLmodule
{
    _JATGL_TLS threadContext;
    _JATGLwindow* windowListHead;
    _JATGLmoduleNS ns;
    CFBundleRef framework;
    int initialized;
};

extern _JATGLmodule _JATGL;

int _JATGLInit(void);
void _JATGLTerminate(void);
void _JATGLGetMousePosition(_JATGLwindow* window, double* xpos, double* ypos);
const char* _JATGLPlatformGetScancodeName(int scancode);

int _JATGLNewWindow(_JATGLwindow* window, int width, int height, const char* title); void _JATGLPlatformDestroyWindow(_JATGLwindow* window);
void _JATGLPlatformGetWindowSize(_JATGLwindow* window, int* width, int* height);
void _JATGLPlatformGetFramebufferSize(_JATGLwindow* window, int* width, int* height);
void _JATGLMakeContextCurrent(_JATGLwindow* window);
void _JATGLSwapBuffers(_JATGLwindow* window);
void* _JATGL_GetGLFunctionAddress(const char* functionName);

void _JATGLPlatformPollEvents(void);

void _JATGLInputKey(_JATGLwindow* window, int key, int scancode, int action);
void _JATGLInputChar(_JATGLwindow* window, unsigned int codepoint, int mods, int plain);
void _JATGLInputMouseClick(_JATGLwindow* window, int button, int action);
void _JATGLInputCursorPos(_JATGLwindow* window, double xpos, double ypos);

#endif // #ifndef __JAKE_GL_INTERNAL_H