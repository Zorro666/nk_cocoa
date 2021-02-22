#include "jake_gl.h"

#include <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#include <mach/mach_time.h>
#include <pthread.h>

typedef TISInputSourceRef (*PFN_TISCopyCurrentKeyboardLayoutInputSource)(void);
typedef void* (*PFN_TISGetInputSourceProperty)(TISInputSourceRef,CFStringRef);
typedef UInt8 (*PFN_LMGetKbdType)(void);

#define kTISPropertyUnicodeKeyLayoutData _JATGL.ns.tis.kPropertyUnicodeKeyLayoutData
#define LMGetKbdType _JATGL.ns.tis.GetKbdType

typedef struct _JATGLwindow
{
    struct _JATGLwindow* next;
    id pixelFormat;
    id object;
    id nsobject;
    id delegate;
    id view;
    id layer;
    int width, height;
    int fbWidth, fbHeight;

    double virtualCursorPosX, virtualCursorPosY;

    int shouldClose;
    char mouseButtons[3];
    char keys[JATGL_KEY_LAST + 1];

    JATGLMouseButtonCallback mouseButtonCallback;
    JATGLCharacterCallback characterCallback;
} _JATGLwindow;

typedef struct JATGL_TLS
{
    pthread_key_t key;
    int allocated;
} JATGL_TLS;

typedef struct _JATGLmoduleNS
{
    CGEventSourceRef    eventSource;
    id                  delegate;
    id                  helper;
    id                  keyUpMonitor;

    short int           keycodes[256];

    struct {
        CFBundleRef     bundle;
        PFN_TISCopyCurrentKeyboardLayoutInputSource CopyCurrentKeyboardLayoutInputSource;
        PFN_LMGetKbdType GetKbdType;
        CFStringRef     kPropertyUnicodeKeyLayoutData;
    } tis;
} _JATGLmoduleNS;

typedef struct JATGLmodule
{
    JATGL_TLS threadContext;
    _JATGLwindow* windowListHead;
    _JATGLmoduleNS ns;
    CFBundleRef framework;
    int initialized;
} JATGLmodule;

static uint64_t s_timer_frequency;
static JATGLmodule _JATGL = { JATGL_FALSE };

static int InitNSGL(void)
{
    if (_JATGL.framework)
        return JATGL_TRUE;

    _JATGL.framework = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
    assert(_JATGL.framework);
    return JATGL_TRUE;
}

static int CreateContextNSGL(_JATGLwindow* window)
{
#define addAttrib(a) \
{ \
    assert((size_t) index < sizeof(attribs) / sizeof(attribs[0])); \
    attribs[index++] = a; \
}
#define setAttrib(a, v) { addAttrib(a); addAttrib(v); }

    NSOpenGLPixelFormatAttribute attribs[40];
    int index = 0;

    addAttrib(NSOpenGLPFAAccelerated);
    addAttrib(NSOpenGLPFAClosestPolicy);

    setAttrib(NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion4_1Core);
    setAttrib(NSOpenGLPFAColorSize, 24);
    setAttrib(NSOpenGLPFAAlphaSize, 8);
    setAttrib(NSOpenGLPFADepthSize, 24);
    setAttrib(NSOpenGLPFAStencilSize, 8);

    addAttrib(NSOpenGLPFADoubleBuffer);

    setAttrib(NSOpenGLPFASampleBuffers, 0);
    addAttrib(0);

#undef addAttrib
#undef setAttrib

    window->pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];
    assert(window->pixelFormat);

    NSOpenGLContext* share = nil;

    window->object = [[NSOpenGLContext alloc] initWithFormat:window->pixelFormat shareContext:share];
    assert(window->object);

    [window->view setWantsBestResolutionOpenGLSurface:true];
    [window->object setView:window->view];
    return JATGL_TRUE;
}

static void CreateKeyTables(void)
{
    int scancode;

    memset(_JATGL.ns.keycodes, -1, sizeof(_JATGL.ns.keycodes));

    _JATGL.ns.keycodes[0x0B] = JATGL_KEY_B;
    _JATGL.ns.keycodes[0x08] = JATGL_KEY_C;
    _JATGL.ns.keycodes[0x0E] = JATGL_KEY_E;
    _JATGL.ns.keycodes[0x0F] = JATGL_KEY_R;
    _JATGL.ns.keycodes[0x09] = JATGL_KEY_V;
    _JATGL.ns.keycodes[0x07] = JATGL_KEY_X;
    _JATGL.ns.keycodes[0x06] = JATGL_KEY_Z;

    _JATGL.ns.keycodes[0x33] = JATGL_KEY_BACKSPACE;
    _JATGL.ns.keycodes[0x75] = JATGL_KEY_DELETE;
    _JATGL.ns.keycodes[0x7D] = JATGL_KEY_DOWN;
    _JATGL.ns.keycodes[0x77] = JATGL_KEY_END;
    _JATGL.ns.keycodes[0x24] = JATGL_KEY_ENTER;
    _JATGL.ns.keycodes[0x73] = JATGL_KEY_HOME;
    _JATGL.ns.keycodes[0x7B] = JATGL_KEY_LEFT;
    _JATGL.ns.keycodes[0x79] = JATGL_KEY_PAGE_DOWN;
    _JATGL.ns.keycodes[0x74] = JATGL_KEY_PAGE_UP;
    _JATGL.ns.keycodes[0x7C] = JATGL_KEY_RIGHT;
    _JATGL.ns.keycodes[0x30] = JATGL_KEY_TAB;
    _JATGL.ns.keycodes[0x7E] = JATGL_KEY_UP;
}

static void InitializeTIS(void)
{
    // This works only because Cocoa has already loaded it properly
    _JATGL.ns.tis.bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.HIToolbox"));
    assert(_JATGL.ns.tis.bundle);

    CFStringRef* kPropertyUnicodeKeyLayoutData = CFBundleGetDataPointerForName(_JATGL.ns.tis.bundle, CFSTR("kTISPropertyUnicodeKeyLayoutData"));
    _JATGL.ns.tis.GetKbdType = CFBundleGetFunctionPointerForName(_JATGL.ns.tis.bundle, CFSTR("LMGetKbdType"));

    if (!kPropertyUnicodeKeyLayoutData || !LMGetKbdType)
    {
        assert(false);
    }

    _JATGL.ns.tis.kPropertyUnicodeKeyLayoutData = *kPropertyUnicodeKeyLayoutData;
}

// Translate a macOS keycode
static int translateKey(unsigned int key)
{
    if (key >= sizeof(_JATGL.ns.keycodes) / sizeof(_JATGL.ns.keycodes[0]))
        return JATGL_KEY_UNKNOWN;

    return _JATGL.ns.keycodes[key];
}

static NSUInteger translateKeyToModifierFlag(int key)
{
    switch (key)
    {
        case JATGL_KEY_LEFT_SHIFT:
        case JATGL_KEY_RIGHT_SHIFT:
            return NSEventModifierFlagShift;
        case JATGL_KEY_LEFT_CONTROL:
        case JATGL_KEY_RIGHT_CONTROL:
            return NSEventModifierFlagControl;
    }

    return 0;
}

static void InputMouseClick(_JATGLwindow* window, int button, int action)
{
    if (button < 0 || button > 2)
        return;

    window->mouseButtons[button] = (char) action;
    if (window->mouseButtonCallback)
        window->mouseButtonCallback((JATGLwindow*) window, button, action, 0);
}

static void InputKey(_JATGLwindow* window, int key, int scancode, int action)
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

void JATGL_SwapBuffers(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window);
    @autoreleasepool
    {
        [window->object flushBuffer];
    }
}

void _JATGLMakeContextCurrent(_JATGLwindow* window)
{
    @autoreleasepool
    {
        if (window)
            [window->object makeCurrentContext];
        else
            [NSOpenGLContext clearCurrentContext];

        assert(_JATGL.threadContext.allocated == JATGL_TRUE);
        pthread_setspecific(_JATGL.threadContext.key, window);
    }
}

void* _JATGL_GetGLFunctionAddress(const char* procname)
{
    CFStringRef symbolName = CFStringCreateWithCString(kCFAllocatorDefault, procname, kCFStringEncodingASCII);
    void* symbol = CFBundleGetFunctionPointerForName(_JATGL.framework, symbolName);
    CFRelease(symbolName);
    return symbol;
}

@interface JATGL_WindowDelegate : NSObject
{
    _JATGLwindow* window;
}

- (instancetype)initWithGlfwWindow:(_JATGLwindow *)initWindow;

@end

@implementation JATGL_WindowDelegate

- (instancetype)initWithGlfwWindow:(_JATGLwindow *)initWindow
{
    self = [super init];
    if (self != nil)
        window = initWindow;

    return self;
}

- (BOOL)windowShouldClose:(id)sender
{
    window->shouldClose = JATGL_TRUE;
    return NO;
}

- (void)windowDidResize:(NSNotification *)notification
{
    [window->object update];

    const NSRect contentRect = [window->view frame];
    const NSRect fbRect = [window->view convertRectToBacking:contentRect];

    if (fbRect.size.width != window->fbWidth ||
        fbRect.size.height != window->fbHeight)
    {
        window->fbWidth  = fbRect.size.width;
        window->fbHeight = fbRect.size.height;
    }

    if (contentRect.size.width != window->width ||
        contentRect.size.height != window->height)
    {
        window->width  = contentRect.size.width;
        window->height = contentRect.size.height;
    }
}
@end

@interface JATGL_ContentView : NSView 
{
    _JATGLwindow* window;
}

- (instancetype)initWithGlfwWindow:(_JATGLwindow *)initWindow;

@end

@implementation JATGL_ContentView

- (instancetype)initWithGlfwWindow:(_JATGLwindow *)initWindow
{
    self = [super init];
    if (self != nil)
    {
        window = initWindow;
    }

    return self;
}

- (void)updateLayer
{
    [window->object update];
}

- (void)mouseDown:(NSEvent *)event
{
    InputMouseClick(window, JATGL_MOUSE_BUTTON_LEFT, JATGL_PRESS);
}

- (void)mouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)mouseUp:(NSEvent *)event
{
    InputMouseClick(window, JATGL_MOUSE_BUTTON_LEFT, JATGL_RELEASE);
}

- (void)mouseMoved:(NSEvent *)event
{
    const NSRect contentRect = [window->view frame];
    const NSPoint pos = [event locationInWindow];
    window->virtualCursorPosX = pos.x;
    window->virtualCursorPosY = contentRect.size.height - pos.y;
}

- (void)rightMouseDown:(NSEvent *)event
{
    InputMouseClick(window, JATGL_MOUSE_BUTTON_RIGHT, JATGL_PRESS);
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    InputMouseClick(window, JATGL_MOUSE_BUTTON_RIGHT, JATGL_RELEASE);
}

- (void)otherMouseDown:(NSEvent *)event
{
    InputMouseClick(window, (int) [event buttonNumber], JATGL_PRESS);
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
    InputMouseClick(window, (int) [event buttonNumber], JATGL_RELEASE);
}

- (void)viewDidChangeBackingProperties
{
    const NSRect contentRect = [window->view frame];
    const NSRect fbRect = [window->view convertRectToBacking:contentRect];

    if (fbRect.size.width != window->fbWidth ||
        fbRect.size.height != window->fbHeight)
    {
        window->fbWidth  = fbRect.size.width;
        window->fbHeight = fbRect.size.height;
    }

    if (window->layer)
        [window->layer setContentsScale:[window->nsobject backingScaleFactor]];
}

- (void)keyDown:(NSEvent *)event
{
    const int key = translateKey([event keyCode]);
    InputKey(window, key, [event keyCode], JATGL_PRESS);
    [self interpretKeyEvents:@[event]];
}

- (void)flagsChanged:(NSEvent *)event
{
    int action;
    const unsigned int modifierFlags =
        [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    const int key = translateKey([event keyCode]);
    const NSUInteger keyFlag = translateKeyToModifierFlag(key);

    if (keyFlag & modifierFlags)
    {
        if (window->keys[key] == JATGL_PRESS)
            action = JATGL_RELEASE;
        else
            action = JATGL_PRESS;
    }
    else
        action = JATGL_RELEASE;

    InputKey(window, key, [event keyCode], action);
}

- (void)keyUp:(NSEvent *)event
{
    const int key = translateKey([event keyCode]);
    InputKey(window, key, [event keyCode], JATGL_RELEASE);
}

@end

static int CreateNativeWindow(_JATGLwindow* window, int width, int height, const char* title)
{
    window->delegate = [[JATGL_WindowDelegate alloc] initWithGlfwWindow:window];
    assert(window->delegate);

    NSRect contentRect;

    contentRect = NSMakeRect(0, 0, width, height);

    window->nsobject = [[NSWindow alloc]
        initWithContentRect:contentRect
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered
        defer:NO];

    assert(window->nsobject);

    [(NSWindow*) window->nsobject center];

    window->view = [[JATGL_ContentView alloc] initWithGlfwWindow:window];

    [window->nsobject setContentView:window->view];
    [window->nsobject makeFirstResponder:window->view];
    [window->nsobject setTitle:@(title)];
    [window->nsobject setDelegate:window->delegate];
    [window->nsobject setAcceptsMouseMovedEvents:YES];
    [window->nsobject setRestorable:NO];

    if ([window->nsobject respondsToSelector:@selector(setTabbingMode:)])
        [window->nsobject setTabbingMode:NSWindowTabbingModeDisallowed];

    JATGL_GetWindowSize((JATGLwindow*)window, &window->width, &window->height);
    JATGL_GetFrameBufferSize((JATGLwindow*)window, &window->fbWidth, &window->fbHeight);

    return JATGL_TRUE;
}

static void Shutdown(void)
{
    while (_JATGL.windowListHead)
        JATGL_DeleteWindow((JATGLwindow*) _JATGL.windowListHead);

    @autoreleasepool
    {
        if (_JATGL.ns.eventSource)
        {
            CFRelease(_JATGL.ns.eventSource);
            _JATGL.ns.eventSource = NULL;
        }

        if (_JATGL.ns.delegate)
        {
            [NSApp setDelegate:nil];
            [_JATGL.ns.delegate release];
            _JATGL.ns.delegate = nil;
        }

        if (_JATGL.ns.helper)
        {
            [[NSNotificationCenter defaultCenter]
                removeObserver:_JATGL.ns.helper
                name:NSTextInputContextKeyboardSelectionDidChangeNotification
                object:nil];
            [[NSNotificationCenter defaultCenter]
                removeObserver:_JATGL.ns.helper];
            [_JATGL.ns.helper release];
            _JATGL.ns.helper = nil;
        }

        if (_JATGL.ns.keyUpMonitor)
            [NSEvent removeMonitor:_JATGL.ns.keyUpMonitor];
    }

    _JATGL.initialized = JATGL_FALSE;

    if (_JATGL.threadContext.allocated)
        pthread_key_delete(_JATGL.threadContext.key);
    _JATGL.threadContext.allocated = 0;
    _JATGL.threadContext.key = 0;

    memset(&_JATGL, 0, sizeof(_JATGL));
}

int _JATGLNewWindow(_JATGLwindow* window, int width, int height, const char* title)
{
    @autoreleasepool
    {
        if (!CreateNativeWindow(window, width, height, title))
            return JATGL_FALSE;

        if (!InitNSGL())
            return JATGL_FALSE;
        if (!CreateContextNSGL(window))
            return JATGL_FALSE;

        [window->nsobject orderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [window->nsobject makeKeyAndOrderFront:nil];

        _JATGLMakeContextCurrent(window);
        return JATGL_TRUE;
    }
}

void JATGL_GetWindowSize(JATGLwindow* handle, int* width, int* height)
{
    _JATGLwindow* window = (_JATGLwindow*)handle;
    assert(window);
    @autoreleasepool
    {
        const NSRect contentRect = [window->view frame];

        if (width)
            *width = contentRect.size.width;
        if (height)
            *height = contentRect.size.height;
    }
}

void JATGL_GetFrameBufferSize(JATGLwindow* handle, int* width, int* height)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window);

    @autoreleasepool
    {
        const NSRect contentRect = [window->view frame];
        const NSRect fbRect = [window->view convertRectToBacking:contentRect];

        if (width)
            *width = (int) fbRect.size.width;
        if (height)
            *height = (int) fbRect.size.height;
    }
}

void JATGL_Poll(void)
{
    @autoreleasepool
    {
        for (;;)
        {
            NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                untilDate:[NSDate distantPast]
                inMode:NSDefaultRunLoopMode
                dequeue:YES];
            if (event == nil)
                break;

            [NSApp sendEvent:event];
        }
    }
}

void JATGL_GetMousePosition(JATGLwindow* handle, double* xpos, double* ypos)
{
    _JATGLwindow* window = (_JATGLwindow*)handle;
    assert(window);
    @autoreleasepool
    {
        const NSRect contentRect = [window->view frame];
        const NSPoint pos = [window->nsobject mouseLocationOutsideOfEventStream];

        if (xpos)
            *xpos = pos.x;
        if (ypos)
            *ypos = contentRect.size.height - pos.y;
    }
}

@interface JATGL_Helper : NSObject
@end

@implementation JATGL_Helper

- (void)doNothing:(id)object
{
}

@end // JATGL_Helper

@interface JATGL_ApplicationDelegate : NSObject <NSApplicationDelegate>
@end

@implementation JATGL_ApplicationDelegate

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    _JATGLwindow* window;

    for (window = _JATGL.windowListHead;  window;  window = window->next)
        window->shouldClose = JATGL_TRUE;

    return NSTerminateCancel;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *) notification
{
    for (_JATGLwindow* window = _JATGL.windowListHead; window; window = window->next)
        [window->object update];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    @autoreleasepool
    {
        NSEvent* event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
            location:NSMakePoint(0, 0)
            modifierFlags:0
            timestamp:0
            windowNumber:0
            context:nil
            subtype:0
            data1:0
            data2:0];
        [NSApp postEvent:event atStart:YES];
        [NSApp stop:nil];
    }
}

@end // JATGL_ApplicationDelegate

int _JATGLInit(void)
{
    @autoreleasepool
    {
        _JATGL.ns.helper = [[JATGL_Helper alloc] init];

        [NSThread detachNewThreadSelector:@selector(doNothing:)
            toTarget:_JATGL.ns.helper
            withObject:nil];

        [NSApplication sharedApplication];

        _JATGL.ns.delegate = [[JATGL_ApplicationDelegate alloc] init];
        assert(_JATGL.ns.delegate);

        [NSApp setDelegate:_JATGL.ns.delegate];

        NSEvent* (^block)(NSEvent*) = ^ NSEvent* (NSEvent* event)
        {
            if ([event modifierFlags] & NSEventModifierFlagCommand)
                [[NSApp keyWindow] sendEvent:event];

            return event;
        };

        _JATGL.ns.keyUpMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp handler:block];

        NSDictionary* defaults = @{@"ApplePressAndHoldEnabled":@NO};
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];

        [[NSNotificationCenter defaultCenter]
            addObserver:_JATGL.ns.helper
            selector:@selector(selectedKeyboardInputSourceChanged:)
            name:NSTextInputContextKeyboardSelectionDidChangeNotification
            object:nil];

        CreateKeyTables();

        _JATGL.ns.eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        if (!_JATGL.ns.eventSource)
            return JATGL_FALSE;

        CGEventSourceSetLocalEventsSuppressionInterval(_JATGL.ns.eventSource, 0.0);

        InitializeTIS();

        if (![[NSRunningApplication currentApplication] isFinishedLaunching])
            [NSApp run];

        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        s_timer_frequency = (info.denom * 1e9) / info.numer;

        return JATGL_TRUE;
    }
}

int JATGL_WindowShouldClose(JATGLwindow* handle)
{
    _JATGLwindow* window = (_JATGLwindow*) handle;
    assert(window);

    return window->shouldClose;
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

int JATGL_Initialize(void)
{
    if (_JATGL.initialized)
        return JATGL_TRUE;

    memset(&_JATGL, 0, sizeof(_JATGL));

    if (!_JATGLInit())
    {
        Shutdown();
        return JATGL_FALSE;
    }

    assert(_JATGL.threadContext.allocated == JATGL_FALSE);
    int result = pthread_key_create(&_JATGL.threadContext.key, NULL);
    assert(result == 0);
    _JATGL.threadContext.allocated = JATGL_TRUE;

    _JATGL.initialized = JATGL_TRUE;
    return JATGL_TRUE;
}

void JATGL_Shutdown(void)
{
    if (!_JATGL.initialized)
        return;
    Shutdown();
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

    assert(_JATGL.threadContext.allocated == JATGL_TRUE);
    if (window == pthread_getspecific(_JATGL.threadContext.key))
        _JATGLMakeContextCurrent(NULL);

    @autoreleasepool
    {
        [window->nsobject orderOut:nil];
        [window->pixelFormat release];
        window->pixelFormat = nil;

        [window->object release];
        window->object = nil;

        [window->nsobject setDelegate:nil];
        [window->delegate release];
        window->delegate = nil;

        [window->view release];
        window->view = nil;

        [window->nsobject close];
        window->nsobject = nil;

        JATGL_Poll();
    }

    _JATGLwindow** prev = &_JATGL.windowListHead;
    while (*prev != window)
        prev = &((*prev)->next);

    *prev = window->next;

    free(window);
}
