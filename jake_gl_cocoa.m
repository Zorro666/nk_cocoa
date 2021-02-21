#include "jake_gl_internal.h"

#include <pthread.h>

#define kTISPropertyUnicodeKeyLayoutData _glfw.ns.tis.kPropertyUnicodeKeyLayoutData
#define TISCopyCurrentKeyboardLayoutInputSource _glfw.ns.tis.CopyCurrentKeyboardLayoutInputSource
#define TISGetInputSourceProperty _glfw.ns.tis.GetInputSourceProperty
#define LMGetKbdType _glfw.ns.tis.GetKbdType

static void SetTLS(_JATGL_TLS* tls, void* value)
{
    assert(tls->allocated == JATGL_TRUE);
    pthread_setspecific(tls->key, value);
}

static void MakeContextCurrentNSGL(_JATGLwindow* window)
{
    @autoreleasepool {

    if (window)
        [window->context.object makeCurrentContext];
    else
        [NSOpenGLContext clearCurrentContext];

    SetTLS(&_glfw.contextSlot, window);

    } // autoreleasepool
}

static GLFWbool InitNSGL(void)
{
    if (_glfw.framework)
        return JATGL_TRUE;

    _glfw.framework = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
    assert(_glfw.framework);
    return JATGL_TRUE;
}

static void SwapBuffersNSGL(_JATGLwindow* window)
{
    @autoreleasepool {

    [window->context.object flushBuffer];

    } // autoreleasepool
}

static JATGLglproc GetProcAddressNSGL(const char* procname)
{
    CFStringRef symbolName = CFStringCreateWithCString(kCFAllocatorDefault, procname, kCFStringEncodingASCII);
    JATGLglproc symbol = CFBundleGetFunctionPointerForName(_glfw.framework, symbolName);
    CFRelease(symbolName);
    return symbol;
}

static void DestroyContextNSGL(_JATGLwindow* window)
{
    @autoreleasepool {

    [window->context.pixelFormat release];
    window->context.pixelFormat = nil;

    [window->context.object release];
    window->context.object = nil;

    } // autoreleasepool
}

static GLFWbool CreateContextNSGL(_JATGLwindow* window)
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

    window->context.pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];
    assert(window->context.pixelFormat);

    NSOpenGLContext* share = nil;

    window->context.object = [[NSOpenGLContext alloc] initWithFormat:window->context.pixelFormat
                                   shareContext:share];
    assert(window->context.object);

    [window->ns.view setWantsBestResolutionOpenGLSurface:true];

    [window->context.object setView:window->ns.view];

    window->context.makeCurrent = MakeContextCurrentNSGL;
    window->context.swapBuffers = SwapBuffersNSGL;
    window->context.getProcAddress = GetProcAddressNSGL;
    window->context.destroy = DestroyContextNSGL;

    return JATGL_TRUE;
}

static void createKeyTables(void)
{
    int scancode;

    memset(_glfw.ns.keycodes, -1, sizeof(_glfw.ns.keycodes));
    memset(_glfw.ns.scancodes, -1, sizeof(_glfw.ns.scancodes));

    _glfw.ns.keycodes[0x0B] = JATGL_KEY_B;
    _glfw.ns.keycodes[0x08] = JATGL_KEY_C;
    _glfw.ns.keycodes[0x0E] = JATGL_KEY_E;
    _glfw.ns.keycodes[0x0F] = JATGL_KEY_R;
    _glfw.ns.keycodes[0x09] = JATGL_KEY_V;
    _glfw.ns.keycodes[0x07] = JATGL_KEY_X;
    _glfw.ns.keycodes[0x06] = JATGL_KEY_Z;

    _glfw.ns.keycodes[0x33] = JATGL_KEY_BACKSPACE;
    _glfw.ns.keycodes[0x75] = JATGL_KEY_DELETE;
    _glfw.ns.keycodes[0x7D] = JATGL_KEY_DOWN;
    _glfw.ns.keycodes[0x77] = JATGL_KEY_END;
    _glfw.ns.keycodes[0x24] = JATGL_KEY_ENTER;
    _glfw.ns.keycodes[0x73] = JATGL_KEY_HOME;
    _glfw.ns.keycodes[0x7B] = JATGL_KEY_LEFT;
    _glfw.ns.keycodes[0x79] = JATGL_KEY_PAGE_DOWN;
    _glfw.ns.keycodes[0x74] = JATGL_KEY_PAGE_UP;
    _glfw.ns.keycodes[0x7C] = JATGL_KEY_RIGHT;
    _glfw.ns.keycodes[0x30] = JATGL_KEY_TAB;
    _glfw.ns.keycodes[0x7E] = JATGL_KEY_UP;

    for (scancode = 0;  scancode < 256;  scancode++)
    {
        // Store the reverse translation for faster key name lookup
        if (_glfw.ns.keycodes[scancode] >= 0)
            _glfw.ns.scancodes[_glfw.ns.keycodes[scancode]] = scancode;
    }
}

static GLFWbool updateUnicodeDataNS(void)
{
    if (_glfw.ns.inputSource)
    {
        CFRelease(_glfw.ns.inputSource);
        _glfw.ns.inputSource = NULL;
        _glfw.ns.unicodeData = nil;
    }

    _glfw.ns.inputSource = TISCopyCurrentKeyboardLayoutInputSource();
    assert(_glfw.ns.inputSource);

    _glfw.ns.unicodeData = TISGetInputSourceProperty(_glfw.ns.inputSource, kTISPropertyUnicodeKeyLayoutData);
    assert(_glfw.ns.unicodeData);
    return JATGL_TRUE;
}

static GLFWbool initializeTIS(void)
{
    // This works only because Cocoa has already loaded it properly
    _glfw.ns.tis.bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.HIToolbox"));
    assert(_glfw.ns.tis.bundle);

    CFStringRef* kPropertyUnicodeKeyLayoutData = CFBundleGetDataPointerForName(_glfw.ns.tis.bundle, CFSTR("kTISPropertyUnicodeKeyLayoutData"));
    _glfw.ns.tis.CopyCurrentKeyboardLayoutInputSource = CFBundleGetFunctionPointerForName(_glfw.ns.tis.bundle, CFSTR("TISCopyCurrentKeyboardLayoutInputSource"));
    _glfw.ns.tis.GetInputSourceProperty = CFBundleGetFunctionPointerForName(_glfw.ns.tis.bundle, CFSTR("TISGetInputSourceProperty"));
    _glfw.ns.tis.GetKbdType = CFBundleGetFunctionPointerForName(_glfw.ns.tis.bundle, CFSTR("LMGetKbdType"));

    if (!kPropertyUnicodeKeyLayoutData || !TISCopyCurrentKeyboardLayoutInputSource || !TISGetInputSourceProperty || !LMGetKbdType)
    {
        assert(false);
    }

    _glfw.ns.tis.kPropertyUnicodeKeyLayoutData = *kPropertyUnicodeKeyLayoutData;

    return updateUnicodeDataNS();
}

// Translate a macOS keycode
static int translateKey(unsigned int key)
{
    if (key >= sizeof(_glfw.ns.keycodes) / sizeof(_glfw.ns.keycodes[0]))
        return JATGL_KEY_UNKNOWN;

    return _glfw.ns.keycodes[key];
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

@interface GLFWWindowDelegate : NSObject
{
    _JATGLwindow* window;
}

- (instancetype)initWithGlfwWindow:(_JATGLwindow *)initWindow;

@end

@implementation GLFWWindowDelegate

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
    [window->context.object update];

    const NSRect contentRect = [window->ns.view frame];
    const NSRect fbRect = [window->ns.view convertRectToBacking:contentRect];

    if (fbRect.size.width != window->ns.fbWidth ||
        fbRect.size.height != window->ns.fbHeight)
    {
        window->ns.fbWidth  = fbRect.size.width;
        window->ns.fbHeight = fbRect.size.height;
    }

    if (contentRect.size.width != window->ns.width ||
        contentRect.size.height != window->ns.height)
    {
        window->ns.width  = contentRect.size.width;
        window->ns.height = contentRect.size.height;
    }
}

@end

@interface GLFWContentView : NSView 
{
    _JATGLwindow* window;
}

- (instancetype)initWithGlfwWindow:(_JATGLwindow *)initWindow;

@end

@implementation GLFWContentView

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
    [window->context.object update];
}

- (void)mouseDown:(NSEvent *)event
{
    _glfwInputMouseClick(window, JATGL_MOUSE_BUTTON_LEFT, JATGL_PRESS);
}

- (void)mouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)mouseUp:(NSEvent *)event
{
    _glfwInputMouseClick(window, JATGL_MOUSE_BUTTON_LEFT, JATGL_RELEASE);
}

- (void)mouseMoved:(NSEvent *)event
{
    {
        const NSRect contentRect = [window->ns.view frame];
        const NSPoint pos = [event locationInWindow];
        _glfwInputCursorPos(window, pos.x, contentRect.size.height - pos.y);
    }
}

- (void)rightMouseDown:(NSEvent *)event
{
    _glfwInputMouseClick(window, JATGL_MOUSE_BUTTON_RIGHT, JATGL_PRESS);
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    _glfwInputMouseClick(window, JATGL_MOUSE_BUTTON_RIGHT, JATGL_RELEASE);
}

- (void)otherMouseDown:(NSEvent *)event
{
    _glfwInputMouseClick(window, (int) [event buttonNumber], JATGL_PRESS);
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
    _glfwInputMouseClick(window, (int) [event buttonNumber], JATGL_RELEASE);
}

- (void)viewDidChangeBackingProperties
{
    const NSRect contentRect = [window->ns.view frame];
    const NSRect fbRect = [window->ns.view convertRectToBacking:contentRect];

    if (fbRect.size.width != window->ns.fbWidth ||
        fbRect.size.height != window->ns.fbHeight)
    {
        window->ns.fbWidth  = fbRect.size.width;
        window->ns.fbHeight = fbRect.size.height;
    }

    if (window->ns.layer)
        [window->ns.layer setContentsScale:[window->ns.object backingScaleFactor]];
}

- (void)keyDown:(NSEvent *)event
{
    const int key = translateKey([event keyCode]);
    _glfwInputKey(window, key, [event keyCode], JATGL_PRESS);

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

    _glfwInputKey(window, key, [event keyCode], action);
}

- (void)keyUp:(NSEvent *)event
{
    const int key = translateKey([event keyCode]);
    _glfwInputKey(window, key, [event keyCode], JATGL_RELEASE);
}

@end

static GLFWbool createNativeWindow(_JATGLwindow* window, const _JATGLwindow_config* wndconfig)
{
    window->ns.delegate = [[GLFWWindowDelegate alloc] initWithGlfwWindow:window];
    assert(window->ns.delegate);

    NSRect contentRect;

    contentRect = NSMakeRect(0, 0, wndconfig->width, wndconfig->height);

    window->ns.object = [[NSWindow alloc]
        initWithContentRect:contentRect
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered
        defer:NO];

    assert(window->ns.object);

    [(NSWindow*) window->ns.object center];

    window->ns.view = [[GLFWContentView alloc] initWithGlfwWindow:window];

    [window->ns.object setContentView:window->ns.view];
    [window->ns.object makeFirstResponder:window->ns.view];
    [window->ns.object setTitle:@(wndconfig->title)];
    [window->ns.object setDelegate:window->ns.delegate];
    [window->ns.object setAcceptsMouseMovedEvents:YES];
    [window->ns.object setRestorable:NO];

    if ([window->ns.object respondsToSelector:@selector(setTabbingMode:)])
        [window->ns.object setTabbingMode:NSWindowTabbingModeDisallowed];

    _glfwPlatformGetWindowSize(window, &window->ns.width, &window->ns.height);
    _glfwPlatformGetFramebufferSize(window, &window->ns.fbWidth, &window->ns.fbHeight);

    return JATGL_TRUE;
}

int _glfwPlatformCreateWindow(_JATGLwindow* window, const _JATGLwindow_config* wndconfig)
{
    @autoreleasepool {

    if (!createNativeWindow(window, wndconfig))
        return JATGL_FALSE;

            if (!InitNSGL())
                return JATGL_FALSE;
            if (!CreateContextNSGL(window))
                return JATGL_FALSE;

    [window->ns.object orderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [window->ns.object makeKeyAndOrderFront:nil];

    return JATGL_TRUE;

    } // autoreleasepool
}

void _glfwPlatformDestroyWindow(_JATGLwindow* window)
{
    @autoreleasepool {

    [window->ns.object orderOut:nil];

    if (window->context.destroy)
        window->context.destroy(window);

    [window->ns.object setDelegate:nil];
    [window->ns.delegate release];
    window->ns.delegate = nil;

    [window->ns.view release];
    window->ns.view = nil;

    [window->ns.object close];
    window->ns.object = nil;

    _glfwPlatformPollEvents();

    } // autoreleasepool
}

void _glfwPlatformGetWindowPos(_JATGLwindow* window, int* xpos, int* ypos)
{
    @autoreleasepool {

    const NSRect contentRect =
        [window->ns.object contentRectForFrameRect:[window->ns.object frame]];

    if (xpos)
        *xpos = contentRect.origin.x;
    if (ypos)
    {
        int y = contentRect.origin.y + contentRect.size.height - 1;
        *ypos = CGDisplayBounds(CGMainDisplayID()).size.height - y - 1;
    }

    } // autoreleasepool
}

void _glfwPlatformGetWindowSize(_JATGLwindow* window, int* width, int* height)
{
    @autoreleasepool {

    const NSRect contentRect = [window->ns.view frame];

    if (width)
        *width = contentRect.size.width;
    if (height)
        *height = contentRect.size.height;

    } // autoreleasepool
}

void _glfwPlatformGetFramebufferSize(_JATGLwindow* window, int* width, int* height)
{
    @autoreleasepool {

    const NSRect contentRect = [window->ns.view frame];
    const NSRect fbRect = [window->ns.view convertRectToBacking:contentRect];

    if (width)
        *width = (int) fbRect.size.width;
    if (height)
        *height = (int) fbRect.size.height;

    } // autoreleasepool
}

void _glfwPlatformPollEvents(void)
{
    @autoreleasepool {

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

    } // autoreleasepool
}

void _glfwPlatformPostEmptyEvent(void)
{
    @autoreleasepool {

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

    } // autoreleasepool
}

void _glfwPlatformGetCursorPos(_JATGLwindow* window, double* xpos, double* ypos)
{
    @autoreleasepool {

    const NSRect contentRect = [window->ns.view frame];
    // NOTE: The returned location uses base 0,1 not 0,0
    const NSPoint pos = [window->ns.object mouseLocationOutsideOfEventStream];

    if (xpos)
        *xpos = pos.x;
    if (ypos)
        *ypos = contentRect.size.height - pos.y;

    } // autoreleasepool
}

const char* _glfwPlatformGetScancodeName(int scancode)
{
    @autoreleasepool {

    assert(scancode >= 0 && scancode <= 0xFF);
    assert(_glfw.ns.keycodes[scancode] != JATGL_KEY_UNKNOWN);

    const int key = _glfw.ns.keycodes[scancode];

    UInt32 deadKeyState = 0;
    UniChar characters[4];
    UniCharCount characterCount = 0;

    if (UCKeyTranslate([(NSData*) _glfw.ns.unicodeData bytes],
                       scancode,
                       kUCKeyActionDisplay,
                       0,
                       LMGetKbdType(),
                       kUCKeyTranslateNoDeadKeysBit,
                       &deadKeyState,
                       sizeof(characters) / sizeof(characters[0]),
                       &characterCount,
                       characters) != noErr)
    {
        return NULL;
    }

    if (!characterCount)
        return NULL;

    CFStringRef string = CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault,
                                                            characters,
                                                            characterCount,
                                                            kCFAllocatorNull);
    CFStringGetCString(string,
                       _glfw.ns.keynames[key],
                       sizeof(_glfw.ns.keynames[key]),
                       kCFStringEncodingUTF8);
    CFRelease(string);

    return _glfw.ns.keynames[key];

    } // autoreleasepool
}

@interface GLFWHelper : NSObject
@end

@implementation GLFWHelper

- (void)selectedKeyboardInputSourceChanged:(NSObject* )object
{
    updateUnicodeDataNS();
}

- (void)doNothing:(id)object
{
}

@end // GLFWHelper

@interface GLFWApplicationDelegate : NSObject <NSApplicationDelegate>
@end

@implementation GLFWApplicationDelegate

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    _JATGLwindow* window;

    for (window = _glfw.windowListHead;  window;  window = window->next)
        window->shouldClose = JATGL_TRUE;

    return NSTerminateCancel;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *) notification
{
    _JATGLwindow* window;

    for (window = _glfw.windowListHead;  window;  window = window->next)
    {
            [window->context.object update];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    _glfwPlatformPostEmptyEvent();
    [NSApp stop:nil];
}

@end // GLFWApplicationDelegate

int _glfwPlatformInit(void)
{
    @autoreleasepool {

    _glfw.ns.helper = [[GLFWHelper alloc] init];

    [NSThread detachNewThreadSelector:@selector(doNothing:)
                             toTarget:_glfw.ns.helper
                           withObject:nil];

    [NSApplication sharedApplication];

    _glfw.ns.delegate = [[GLFWApplicationDelegate alloc] init];
    assert(_glfw.ns.delegate);

    [NSApp setDelegate:_glfw.ns.delegate];

    NSEvent* (^block)(NSEvent*) = ^ NSEvent* (NSEvent* event)
    {
        if ([event modifierFlags] & NSEventModifierFlagCommand)
            [[NSApp keyWindow] sendEvent:event];

        return event;
    };

    _glfw.ns.keyUpMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp handler:block];

    NSDictionary* defaults = @{@"ApplePressAndHoldEnabled":@NO};
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];

    [[NSNotificationCenter defaultCenter]
        addObserver:_glfw.ns.helper
           selector:@selector(selectedKeyboardInputSourceChanged:)
               name:NSTextInputContextKeyboardSelectionDidChangeNotification
             object:nil];

    createKeyTables();

    _glfw.ns.eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!_glfw.ns.eventSource)
        return JATGL_FALSE;

    CGEventSourceSetLocalEventsSuppressionInterval(_glfw.ns.eventSource, 0.0);

    if (!initializeTIS())
        return JATGL_FALSE;

    if (![[NSRunningApplication currentApplication] isFinishedLaunching])
        [NSApp run];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    return JATGL_TRUE;

    } // autoreleasepool
}

void _glfwPlatformTerminate(void)
{
    @autoreleasepool {

    if (_glfw.ns.inputSource)
    {
        CFRelease(_glfw.ns.inputSource);
        _glfw.ns.inputSource = NULL;
        _glfw.ns.unicodeData = nil;
    }

    if (_glfw.ns.eventSource)
    {
        CFRelease(_glfw.ns.eventSource);
        _glfw.ns.eventSource = NULL;
    }

    if (_glfw.ns.delegate)
    {
        [NSApp setDelegate:nil];
        [_glfw.ns.delegate release];
        _glfw.ns.delegate = nil;
    }

    if (_glfw.ns.helper)
    {
        [[NSNotificationCenter defaultCenter]
            removeObserver:_glfw.ns.helper
                      name:NSTextInputContextKeyboardSelectionDidChangeNotification
                    object:nil];
        [[NSNotificationCenter defaultCenter]
            removeObserver:_glfw.ns.helper];
        [_glfw.ns.helper release];
        _glfw.ns.helper = nil;
    }

    if (_glfw.ns.keyUpMonitor)
        [NSEvent removeMonitor:_glfw.ns.keyUpMonitor];

    } // autoreleasepool
}
