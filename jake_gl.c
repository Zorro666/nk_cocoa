#include "jake_gl_internal.h"

#include <pthread.h>
#include <mach/mach_time.h>

_JATGLmodule _JATGL = { JATGL_FALSE };

#define _JATGL_SWAP_POINTERS(x, y) \
    {                             \
        void* t;                  \
        t = x;                    \
        x = y;                    \
        y = t;                    \
    }

static int _JATGLPlatformGetKeyScancode(int key)
{
    return _JATGL.ns.scancodes[key];
}

static void InitTimerNS(void)
{
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);

    _JATGL.timer.frequency = (info.denom * 1e9) / info.numer;
}

static GLFWbool CreateTLS(_JATGL_TLS* tls)
{
    assert(tls->allocated == JATGL_FALSE);

    int result = pthread_key_create(&tls->key, NULL);
    assert(result == 0);
    tls->allocated = JATGL_TRUE;
    return JATGL_TRUE;
}

static void DestroyTLS(_JATGL_TLS* tls)
{
    if (tls->allocated)
        pthread_key_delete(tls->key);
    memset(tls, 0, sizeof(_JATGL_TLS));
}

static void* GetTLS(_JATGL_TLS* tls)
{
    assert(tls->allocated == JATGL_TRUE);
    return pthread_getspecific(tls->key);
}

static _JATGLwindow* GetCurrentContext(void)
{
    return GetTLS(&_JATGL.contextSlot);
}


static void terminate(void)
{
    while (_JATGL.windowListHead)
        JATGL_DeleteWindow((JATGLwindow*) _JATGL.windowListHead);

    _JATGLPlatformTerminate();

    _JATGL.initialized = JATGL_FALSE;

    DestroyTLS(&_JATGL.contextSlot);

    memset(&_JATGL, 0, sizeof(_JATGL));
}

static GLFWbool RefreshContextAttribs(_JATGLwindow* window)
{
    _JATGLwindow* previous;

    previous = GetCurrentContext();
    JATGL_MakeContextCurrent((JATGLwindow*) window);

    window->context.GetIntegerv = (PFNGLGETINTEGERVPROC)window->context.getProcAddress("glGetIntegerv");
    window->context.GetString = (PFNGLGETSTRINGPROC)window->context.getProcAddress("glGetString");
    assert(window->context.GetIntegerv);
    assert(window->context.GetString);

    window->context.GetStringi = (PFNGLGETSTRINGIPROC)window->context.getProcAddress("glGetStringi");
    assert(window->context.GetStringi);

    PFNGLCLEARPROC glClear = (PFNGLCLEARPROC)window->context.getProcAddress("glClear");
    glClear(GL_COLOR_BUFFER_BIT);
    window->context.swapBuffers(window);

    JATGL_MakeContextCurrent((JATGLwindow*) previous);
    return JATGL_TRUE;
}

JATGLwindow* JATGL_NewWindow(int width, int height, const char* title)
{
    _JATGLwindow_config wndconfig;
    _JATGLwindow* window;

    assert(title != NULL);
    assert(width >= 0);
    assert(height >= 0);

    memset(&wndconfig, 0, sizeof(wndconfig));
 
    wndconfig.width   = width;
    wndconfig.height  = height;
    wndconfig.title   = title;

    window = calloc(1, sizeof(_JATGLwindow));
    window->next = _JATGL.windowListHead;
    _JATGL.windowListHead = window;

    // Open the actual window and create its context
    if (!_JATGLPlatformCreateWindow(window, &wndconfig))
    {
        JATGL_DeleteWindow((JATGLwindow*) window);
        return NULL;
    }

    {
        if (!RefreshContextAttribs(window))
        {
            JATGL_DeleteWindow((JATGLwindow*) window);
            return NULL;
        }
    }

    JATGL_MakeContextCurrent((JATGLwindow*)window);
    return (JATGLwindow*) window;
}

void JATGL_DeleteWindow(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;

    if (window == NULL)
        return;

    memset(&window->callbacks, 0, sizeof(window->callbacks));

    if (window == GetCurrentContext())
        JATGL_MakeContextCurrent(NULL);

    _JATGLPlatformDestroyWindow(window);

    {
        _JATGLwindow** prev = &_JATGL.windowListHead;
        while (*prev != window)
            prev = &((*prev)->next);

        *prev = window->next;
    }

    free(window);
}

int JATGL_WindowShouldClose(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    return window->shouldClose;
}

void JATGL_GetWindowSize(JATGLwindow* handle, int* width, int* height)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    if (width)
        *width = 0;
    if (height)
        *height = 0;

    _JATGLPlatformGetWindowSize(window, width, height);
}

void JATGL_GetFrameBufferSize(JATGLwindow* handle, int* width, int* height)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    if (width)
        *width = 0;
    if (height)
        *height = 0;

    _JATGLPlatformGetFramebufferSize(window, width, height);
}

void JATGL_Poll(void)
{
    _JATGLPlatformPollEvents();
}

void JATGL_MakeContextCurrent(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    _JATGLwindow* previous = GetCurrentContext();

    if (previous)
    {
        if (!window)
            previous->context.makeCurrent(NULL);
    }

    if (window)
        window->context.makeCurrent(window);
}

void JATGL_SwapBuffers(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    window->context.swapBuffers(window);
}

JATGLglproc JATGL_GetGLProcAddress(const char* procname)
{
    _JATGLwindow* window;
    assert(procname != NULL);

    window = GetCurrentContext();
    assert(window);

    return window->context.getProcAddress(procname);
}

int JATGL_Initialize(void)
{
    if (_JATGL.initialized)
        return JATGL_TRUE;

    memset(&_JATGL, 0, sizeof(_JATGL));

    if (!_JATGLPlatformInit())
    {
        terminate();
        return JATGL_FALSE;
    }

    if (!CreateTLS(&_JATGL.contextSlot))
    {
        terminate();
        return JATGL_FALSE;
    }

    InitTimerNS();

    _JATGL.initialized = JATGL_TRUE;
    return JATGL_TRUE;
}

void JATGL_Shutdown(void)
{
    if (!_JATGL.initialized)
        return;

    terminate();
}

void _JATGLInputKey(_JATGLwindow* window, int key, int scancode, int action)
{
    if (key >= 0 && key <= JATGL_KEY_LAST)
    {
        GLFWbool repeated = JATGL_FALSE;

        if (action == JATGL_RELEASE && window->keys[key] == JATGL_RELEASE)
            return;

        if (action == JATGL_PRESS && window->keys[key] == JATGL_PRESS)
            repeated = JATGL_TRUE;

            window->keys[key] = (char) action;
    }
}

void _JATGLInputChar(_JATGLwindow* window, unsigned int codepoint, int mods, GLFWbool plain)
{
    if (codepoint < 32 || (codepoint > 126 && codepoint < 160))
        return;

    if (plain)
    {
        if (window->callbacks.character)
            window->callbacks.character((JATGLwindow*) window, codepoint);
    }
}

void _JATGLInputMouseClick(_JATGLwindow* window, int button, int action)
{
    if (button < 0 || button > 2)
        return;

    window->mouseButtons[button] = (char) action;
    if (window->callbacks.mouseButton)
        window->callbacks.mouseButton((JATGLwindow*) window, button, action, 0);
}

void _JATGLInputCursorPos(_JATGLwindow* window, double xpos, double ypos)
{
    window->virtualCursorPosX = xpos;
    window->virtualCursorPosY = ypos;
}

const char* JATGL_GetKeyStateName(int key, int scancode)
{
    if (key != JATGL_KEY_UNKNOWN)
    {
        scancode = _JATGLPlatformGetKeyScancode(key);
    }

    return _JATGLPlatformGetScancodeName(scancode);
}

int JATGL_GetKeyStateScancode(int key)
{
    assert(key >= JATGL_KEY_FIRST && key <= JATGL_KEY_LAST);
    return _JATGLPlatformGetKeyScancode(key);
}

int JATGL_GetKeyState(JATGLwindow* handle, int key)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    assert(key >= JATGL_KEY_FIRST && key <= JATGL_KEY_LAST);

    return (int) window->keys[key];
}

int JATGL_GetMouseButtonState(JATGLwindow* handle, int button)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    assert(button >= 0 && button <= 2);
    return (int) window->mouseButtons[button];
}

void JATGL_GetMousePosition(JATGLwindow* handle, double* xpos, double* ypos)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    if (xpos)
        *xpos = 0;
    if (ypos)
        *ypos = 0;

    _JATGLPlatformGetCursorPos(window, xpos, ypos);
}

JATGLcharacter_function JATGL_SetCharacterCallback(JATGLwindow* handle, JATGLcharacter_function cbfun)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    _JATGL_SWAP_POINTERS(window->callbacks.character, cbfun);
    return cbfun;
}

JATGLmouse_button_function JATGL_SetMouseButtonCallback(JATGLwindow* handle,
                                                      JATGLmouse_button_function cbfun)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window != NULL);

    _JATGL_SWAP_POINTERS(window->callbacks.mouseButton, cbfun);
    return cbfun;
}

double JATGL_GetTime(void)
{
    uint64_t frequency = _JATGL.timer.frequency;
    return (double) (mach_absolute_time() - _JATGL.timer.offset) / frequency;
}
