#include "jake_gl_internal.h"

#include <pthread.h>
#include <mach/mach_time.h>

#define GL_COLOR_BUFFER_BIT 0x00004000

_JATGLmodule _JATGL = { JATGL_FALSE };

static uint64_t s_timer_frequency;

static int _JATGLPlatformGetKeyScancode(int key)
{
    return _JATGL.ns.scancodes[key];
}

static int CreateTLS(_JATGL_TLS* tls)
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
    return GetTLS(&_JATGL.threadContext);
}

static void Terminate(void)
{
    while (_JATGL.windowListHead)
        JATGL_DeleteWindow((JATGLwindow*) _JATGL.windowListHead);

    _JATGLTerminate();
    _JATGL.initialized = JATGL_FALSE;
    DestroyTLS(&_JATGL.threadContext);
    memset(&_JATGL, 0, sizeof(_JATGL));
}

JATGLwindow* JATGL_NewWindow(int width, int height, const char* title)
{
    _JATGLwindow* window;

    assert(title);
    assert(width >= 0);
    assert(height >= 0);

    window = calloc(1, sizeof(_JATGLwindow));
    window->next = _JATGL.windowListHead;
    _JATGL.windowListHead = window;

    if (!_JATGLNewWindow(window, width, height, title))
    {
        JATGL_DeleteWindow((JATGLwindow*) window);
        return NULL;
    }
    return (JATGLwindow*)window;
}

void JATGL_DeleteWindow(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;

    if (window == NULL)
        return;

    window->characterCallback = NULL;
    window->mouseButtonCallback = NULL;

    if (window == GetCurrentContext())
        _JATGLMakeContextCurrent(NULL);

    _JATGLPlatformDestroyWindow(window);

    _JATGLwindow** prev = &_JATGL.windowListHead;
    while (*prev != window)
        prev = &((*prev)->next);

    *prev = window->next;

    free(window);
}

int JATGL_WindowShouldClose(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window);

    return window->shouldClose;
}

void JATGL_GetWindowSize(JATGLwindow* handle, int* width, int* height)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window);

    if (width)
        *width = 0;
    if (height)
        *height = 0;

    _JATGLPlatformGetWindowSize(window, width, height);
}

void JATGL_GetFrameBufferSize(JATGLwindow* handle, int* width, int* height)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window);

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

/*
void JATGL_MakeContextCurrent(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    _JATGLwindow* previous = GetCurrentContext();

    if (previous)
    {
        if (!window)
            _JATGLMakeContextCurrent(NULL);
    }
    if (window)
        _JATGLMakeContextCurrent(window);
}
*/

void JATGL_SwapBuffers(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window);

    _JATGLSwapBuffers(window);
}

int JATGL_Initialize(void)
{
    if (_JATGL.initialized)
        return JATGL_TRUE;

    memset(&_JATGL, 0, sizeof(_JATGL));

    if (!_JATGLInit())
    {
        Terminate();
        return JATGL_FALSE;
    }

    if (!CreateTLS(&_JATGL.threadContext))
    {
        Terminate();
        return JATGL_FALSE;
    }

    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    s_timer_frequency = (info.denom * 1e9) / info.numer;

    _JATGL.initialized = JATGL_TRUE;
    return JATGL_TRUE;
}

void JATGL_Shutdown(void)
{
    if (!_JATGL.initialized)
        return;
    Terminate();
}

void _JATGLInputKey(_JATGLwindow* window, int key, int scancode, int action)
{
    if (key >= 0 && key <= JATGL_KEY_LAST)
    {
        int repeated = JATGL_FALSE;

        if (action == JATGL_RELEASE && window->keys[key] == JATGL_RELEASE)
            return;

        if (action == JATGL_PRESS && window->keys[key] == JATGL_PRESS)
            repeated = JATGL_TRUE;

            window->keys[key] = (char) action;
    }
}

void _JATGLInputChar(_JATGLwindow* window, unsigned int codepoint, int mods, int plain)
{
    if (codepoint < 32 || (codepoint > 126 && codepoint < 160))
        return;

    if (plain)
    {
        if (window->characterCallback)
            window->characterCallback((JATGLwindow*) window, codepoint);
    }
}

void _JATGLInputMouseClick(_JATGLwindow* window, int button, int action)
{
    if (button < 0 || button > 2)
        return;

    window->mouseButtons[button] = (char) action;
    if (window->mouseButtonCallback)
        window->mouseButtonCallback((JATGLwindow*) window, button, action, 0);
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
    assert(window);

    assert(key >= JATGL_KEY_FIRST && key <= JATGL_KEY_LAST);

    return (int) window->keys[key];
}

int JATGL_GetMouseButtonState(JATGLwindow* handle, int button)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window);

    assert(button >= 0 && button <= 2);
    return (int) window->mouseButtons[button];
}

void JATGL_GetMousePosition(JATGLwindow* handle, double* xpos, double* ypos)
{
    _JATGLwindow* window = (_JATGLwindow*)handle;
    assert(window);
    _JATGLGetMousePosition(window, xpos, ypos);
}

void JATGL_SetCharacterCallback(JATGLwindow* handle, JATGLCharacterCallback callback)
{
    _JATGLwindow* window = (_JATGLwindow*)handle;
    assert(window);
    window->characterCallback = callback;
}

void JATGL_SetMouseButtonCallback(JATGLwindow* handle, JATGLMouseButtonCallback callback)
{
    _JATGLwindow* window = (_JATGLwindow*)handle;
    assert(window);
    window->mouseButtonCallback = callback;
}

double JATGL_GetTime(void)
{
    return (double)mach_absolute_time() / s_timer_frequency;
}
