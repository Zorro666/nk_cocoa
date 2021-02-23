#include "jake_gl.h"

#include <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#include <mach/mach_time.h>
#include <pthread.h>

typedef struct JATGL_Window
{
  struct JATGL_Window *next;
  id pixelFormat;
  id object;
  id nsobject;
  id delegate;
  id view;
  id layer;
  int width, height;
  int fbWidth, fbHeight;
  int shouldClose;
  char mouseButtons[3];
  char keys[JATGL_KEY_LAST + 1];

  JATGLMouseButtonCallback mouseButtonCallback;
  JATGLCharacterCallback characterCallback;
} JATGL_Window;

typedef struct JATGL_TLS
{
  pthread_key_t key;
  int allocated;
} JATGL_TLS;

typedef struct JATGLmodule
{
  JATGL_TLS threadContext;
  JATGL_Window *windowListHead;
  CFBundleRef framework;
  CGEventSourceRef eventSource;
  id delegate;
  id helper;
  id keyUpMonitor;
  uint64_t timer_frequency;

  short int keycodes[256];
  int initialized;
} JATGLmodule;

static JATGLmodule s_JATGL = {JATGL_FALSE};

static void MakeContextCurrent(JATGL_Window *window)
{
  @autoreleasepool
  {
    if(window)
      [window->object makeCurrentContext];
    else
      [NSOpenGLContext clearCurrentContext];

    assert(s_JATGL.threadContext.allocated == JATGL_TRUE);
    pthread_setspecific(s_JATGL.threadContext.key, window);
  }
}

static void CreateContextNSGL(JATGL_Window *window)
{
  assert(!s_JATGL.framework);
  s_JATGL.framework = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
  assert(s_JATGL.framework);

#define addAttrib(a)                                              \
  {                                                               \
    assert((size_t)index < sizeof(attribs) / sizeof(attribs[0])); \
    attribs[index++] = a;                                         \
  }
#define setAttrib(a, v) \
  {                     \
    addAttrib(a);       \
    addAttrib(v);       \
  }

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

  NSOpenGLContext *share = nil;

  window->object = [[NSOpenGLContext alloc] initWithFormat:window->pixelFormat shareContext:share];
  assert(window->object);

  [window->view setWantsBestResolutionOpenGLSurface:true];
  [window->object setView:window->view];

  [window->nsobject orderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  [window->nsobject makeKeyAndOrderFront:nil];

  MakeContextCurrent(window);
}

static void CreateKeyTables(void)
{
  int scancode;

  memset(s_JATGL.keycodes, -1, sizeof(s_JATGL.keycodes));

  s_JATGL.keycodes[0x0B] = JATGL_KEY_B;
  s_JATGL.keycodes[0x08] = JATGL_KEY_C;
  s_JATGL.keycodes[0x0E] = JATGL_KEY_E;
  s_JATGL.keycodes[0x0F] = JATGL_KEY_R;
  s_JATGL.keycodes[0x09] = JATGL_KEY_V;
  s_JATGL.keycodes[0x07] = JATGL_KEY_X;
  s_JATGL.keycodes[0x06] = JATGL_KEY_Z;
  s_JATGL.keycodes[0x33] = JATGL_KEY_BACKSPACE;
  s_JATGL.keycodes[0x75] = JATGL_KEY_DELETE;
  s_JATGL.keycodes[0x7D] = JATGL_KEY_DOWN;
  s_JATGL.keycodes[0x77] = JATGL_KEY_END;
  s_JATGL.keycodes[0x24] = JATGL_KEY_ENTER;
  s_JATGL.keycodes[0x73] = JATGL_KEY_HOME;
  s_JATGL.keycodes[0x7B] = JATGL_KEY_LEFT;
  s_JATGL.keycodes[0x79] = JATGL_KEY_PAGE_DOWN;
  s_JATGL.keycodes[0x74] = JATGL_KEY_PAGE_UP;
  s_JATGL.keycodes[0x7C] = JATGL_KEY_RIGHT;
  s_JATGL.keycodes[0x30] = JATGL_KEY_TAB;
  s_JATGL.keycodes[0x7E] = JATGL_KEY_UP;
}

// Translate a macOS keycode
static int TranslateKey(unsigned int key)
{
  if(key >= sizeof(s_JATGL.keycodes) / sizeof(s_JATGL.keycodes[0]))
    return JATGL_KEY_UNKNOWN;

  return s_JATGL.keycodes[key];
}

static NSUInteger TranslateKeyToModifierFlag(int key)
{
  switch(key)
  {
    case JATGL_KEY_LEFT_SHIFT:
    case JATGL_KEY_RIGHT_SHIFT: return NSEventModifierFlagShift;
    case JATGL_KEY_LEFT_CONTROL:
    case JATGL_KEY_RIGHT_CONTROL: return NSEventModifierFlagControl;
  }

  return 0;
}

static void InputMouseClick(JATGL_Window *window, int button, int action)
{
  if(button < 0 || button > 2)
    return;

  window->mouseButtons[button] = (char)action;
  if(window->mouseButtonCallback)
    window->mouseButtonCallback((JATGLwindow *)window, button, action, 0);
}

static void InputKey(JATGL_Window *window, int key, int scancode, int action)
{
  if(key >= 0 && key <= JATGL_KEY_LAST)
  {
    int repeated = JATGL_FALSE;

    if(action == JATGL_RELEASE && window->keys[key] == JATGL_RELEASE)
      return;

    if(action == JATGL_PRESS && window->keys[key] == JATGL_PRESS)
      repeated = JATGL_TRUE;

    window->keys[key] = (char)action;
  }
}

void JATGL_SwapBuffers(JATGLwindow *handle)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  @autoreleasepool
  {
    [window->object flushBuffer];
  }
}

void *_JATGL_GetGLFunctionAddress(const char *procname)
{
  CFStringRef symbolName =
      CFStringCreateWithCString(kCFAllocatorDefault, procname, kCFStringEncodingASCII);
  void *symbol = CFBundleGetFunctionPointerForName(s_JATGL.framework, symbolName);
  CFRelease(symbolName);
  return symbol;
}

@interface JATGL_WindowDelegate : NSObject
{
  JATGL_Window *window;
}

- (instancetype)initWithGlfwWindow:(JATGL_Window *)initWindow;

@end

@implementation JATGL_WindowDelegate

- (instancetype)initWithGlfwWindow:(JATGL_Window *)initWindow
{
  self = [super init];
  if(self != nil)
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

  if(fbRect.size.width != window->fbWidth || fbRect.size.height != window->fbHeight)
  {
    window->fbWidth = fbRect.size.width;
    window->fbHeight = fbRect.size.height;
  }

  if(contentRect.size.width != window->width || contentRect.size.height != window->height)
  {
    window->width = contentRect.size.width;
    window->height = contentRect.size.height;
  }
}
@end

@interface JATGL_ContentView : NSView
{
  JATGL_Window *window;
}

- (instancetype)initWithGlfwWindow:(JATGL_Window *)initWindow;

@end

@implementation JATGL_ContentView

- (instancetype)initWithGlfwWindow:(JATGL_Window *)initWindow
{
  self = [super init];
  if(self != nil)
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
  InputMouseClick(window, (int)[event buttonNumber], JATGL_PRESS);
}

- (void)otherMouseDragged:(NSEvent *)event
{
  [self mouseMoved:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
  InputMouseClick(window, (int)[event buttonNumber], JATGL_RELEASE);
}

- (void)viewDidChangeBackingProperties
{
  const NSRect contentRect = [window->view frame];
  const NSRect fbRect = [window->view convertRectToBacking:contentRect];

  if(fbRect.size.width != window->fbWidth || fbRect.size.height != window->fbHeight)
  {
    window->fbWidth = fbRect.size.width;
    window->fbHeight = fbRect.size.height;
  }

  if(window->layer)
    [window->layer setContentsScale:[window->nsobject backingScaleFactor]];
}

- (void)keyDown:(NSEvent *)event
{
  const int key = TranslateKey([event keyCode]);
  InputKey(window, key, [event keyCode], JATGL_PRESS);
  [self interpretKeyEvents:@[ event ]];
}

- (void)flagsChanged:(NSEvent *)event
{
  int action;
  const unsigned int modifierFlags =
      [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
  const int key = TranslateKey([event keyCode]);
  const NSUInteger keyFlag = TranslateKeyToModifierFlag(key);

  if(keyFlag & modifierFlags)
  {
    if(window->keys[key] == JATGL_PRESS)
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
  const int key = TranslateKey([event keyCode]);
  InputKey(window, key, [event keyCode], JATGL_RELEASE);
}

@end

static int CreateNativeWindow(JATGL_Window *window, int width, int height, const char *title)
{
  window->delegate = [[JATGL_WindowDelegate alloc] initWithGlfwWindow:window];
  assert(window->delegate);

  NSRect contentRect;

  contentRect = NSMakeRect(0, 0, width, height);

  window->nsobject =
      [[NSWindow alloc] initWithContentRect:contentRect
                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                    backing:NSBackingStoreBuffered
                                      defer:NO];

  assert(window->nsobject);

  [(NSWindow *)window->nsobject center];

  window->view = [[JATGL_ContentView alloc] initWithGlfwWindow:window];

  [window->nsobject setContentView:window->view];
  [window->nsobject makeFirstResponder:window->view];
  [window->nsobject setTitle:@(title)];
  [window->nsobject setDelegate:window->delegate];
  [window->nsobject setAcceptsMouseMovedEvents:YES];
  [window->nsobject setRestorable:NO];

  if([window->nsobject respondsToSelector:@selector(setTabbingMode:)])
    [window->nsobject setTabbingMode:NSWindowTabbingModeDisallowed];

  JATGL_GetWindowSize((JATGLwindow *)window, &window->width, &window->height);
  JATGL_GetFrameBufferSize((JATGLwindow *)window, &window->fbWidth, &window->fbHeight);

  return JATGL_TRUE;
}

static void Shutdown(void)
{
  while(s_JATGL.windowListHead)
    JATGL_DeleteWindow((JATGLwindow *)s_JATGL.windowListHead);

  @autoreleasepool
  {
    if(s_JATGL.eventSource)
    {
      CFRelease(s_JATGL.eventSource);
      s_JATGL.eventSource = NULL;
    }

    if(s_JATGL.delegate)
    {
      [NSApp setDelegate:nil];
      [s_JATGL.delegate release];
      s_JATGL.delegate = nil;
    }

    if(s_JATGL.helper)
    {
      [[NSNotificationCenter defaultCenter]
          removeObserver:s_JATGL.helper
                    name:NSTextInputContextKeyboardSelectionDidChangeNotification
                  object:nil];
      [[NSNotificationCenter defaultCenter] removeObserver:s_JATGL.helper];
      [s_JATGL.helper release];
      s_JATGL.helper = nil;
    }

    if(s_JATGL.keyUpMonitor)
      [NSEvent removeMonitor:s_JATGL.keyUpMonitor];
  }

  if(s_JATGL.threadContext.allocated)
    pthread_key_delete(s_JATGL.threadContext.key);

  memset(&s_JATGL, 0, sizeof(s_JATGL));
}

void JATGL_GetWindowSize(JATGLwindow *handle, int *width, int *height)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  @autoreleasepool
  {
    const NSRect contentRect = [window->view frame];

    if(width)
      *width = contentRect.size.width;
    if(height)
      *height = contentRect.size.height;
  }
}

void JATGL_GetFrameBufferSize(JATGLwindow *handle, int *width, int *height)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);

  @autoreleasepool
  {
    const NSRect contentRect = [window->view frame];
    const NSRect fbRect = [window->view convertRectToBacking:contentRect];

    if(width)
      *width = (int)fbRect.size.width;
    if(height)
      *height = (int)fbRect.size.height;
  }
}

void JATGL_Poll(void)
{
  @autoreleasepool
  {
    for(;;)
    {
      NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                          untilDate:[NSDate distantPast]
                                             inMode:NSDefaultRunLoopMode
                                            dequeue:YES];
      if(event == nil)
        break;

      [NSApp sendEvent:event];
    }
  }
}

void JATGL_GetMousePosition(JATGLwindow *handle, double *xpos, double *ypos)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  @autoreleasepool
  {
    const NSRect contentRect = [window->view frame];
    const NSPoint pos = [window->nsobject mouseLocationOutsideOfEventStream];

    if(xpos)
      *xpos = pos.x;
    if(ypos)
      *ypos = contentRect.size.height - pos.y;
  }
}

@interface JATGL_Helper : NSObject
@end

@implementation JATGL_Helper

- (void)doNothing:(id)object
{
}

@end    // JATGL_Helper

@interface JATGL_ApplicationDelegate : NSObject<NSApplicationDelegate>
@end

@implementation JATGL_ApplicationDelegate

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
  JATGL_Window *window;

  for(window = s_JATGL.windowListHead; window; window = window->next)
    window->shouldClose = JATGL_TRUE;

  return NSTerminateCancel;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification
{
  for(JATGL_Window *window = s_JATGL.windowListHead; window; window = window->next)
    [window->object update];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  @autoreleasepool
  {
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
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

@end    // JATGL_ApplicationDelegate

int JATGL_WindowShouldClose(JATGLwindow *handle)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);

  return window->shouldClose;
}

void JATGL_SetCharacterCallback(JATGLwindow *handle, JATGLCharacterCallback callback)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  window->characterCallback = callback;
}

void JATGL_SetMouseButtonCallback(JATGLwindow *handle, JATGLMouseButtonCallback callback)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  window->mouseButtonCallback = callback;
}

double JATGL_GetTime(void)
{
  return (double)mach_absolute_time() / s_JATGL.timer_frequency;
}

int JATGL_GetKeyState(JATGLwindow *handle, int key)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  assert(key >= JATGL_KEY_FIRST && key <= JATGL_KEY_LAST);
  return (int)window->keys[key];
}

int JATGL_GetMouseButtonState(JATGLwindow *handle, int button)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  assert(button >= 0 && button <= 2);
  return (int)window->mouseButtons[button];
}

int JATGL_Initialize(void)
{
  if(s_JATGL.initialized)
    return JATGL_TRUE;

  memset(&s_JATGL, 0, sizeof(s_JATGL));

  @autoreleasepool
  {
    s_JATGL.helper = [[JATGL_Helper alloc] init];

    [NSThread detachNewThreadSelector:@selector(doNothing:) toTarget:s_JATGL.helper withObject:nil];

    [NSApplication sharedApplication];

    s_JATGL.delegate = [[JATGL_ApplicationDelegate alloc] init];
    assert(s_JATGL.delegate);

    [NSApp setDelegate:s_JATGL.delegate];

    NSEvent * (^block)(NSEvent *) = ^NSEvent *(NSEvent *event)
    {
      if([event modifierFlags] & NSEventModifierFlagCommand)
        [[NSApp keyWindow] sendEvent:event];
      return event;
    };

    s_JATGL.keyUpMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp handler:block];

    NSDictionary *defaults = @{ @"ApplePressAndHoldEnabled" : @NO };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];

    [[NSNotificationCenter defaultCenter]
        addObserver:s_JATGL.helper
           selector:@selector(selectedKeyboardInputSourceChanged:)
               name:NSTextInputContextKeyboardSelectionDidChangeNotification
             object:nil];

    CreateKeyTables();

    s_JATGL.eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if(!s_JATGL.eventSource)
    {
      Shutdown();
      return JATGL_FALSE;
    }

    CGEventSourceSetLocalEventsSuppressionInterval(s_JATGL.eventSource, 0.0);

    if(![[NSRunningApplication currentApplication] isFinishedLaunching])
      [NSApp run];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  }

  mach_timebase_info_data_t info;
  mach_timebase_info(&info);
  s_JATGL.timer_frequency = (info.denom * 1e9) / info.numer;

  assert(s_JATGL.threadContext.allocated == JATGL_FALSE);
  int result = pthread_key_create(&s_JATGL.threadContext.key, NULL);
  assert(result == 0);
  s_JATGL.threadContext.allocated = JATGL_TRUE;

  s_JATGL.initialized = JATGL_TRUE;
  return JATGL_TRUE;
}

void JATGL_Shutdown(void)
{
  if(!s_JATGL.initialized)
    return;
  Shutdown();
}

JATGLwindow *JATGL_NewWindow(int width, int height, const char *title)
{
  JATGL_Window *window;

  assert(title);
  assert(width >= 0);
  assert(height >= 0);

  window = calloc(1, sizeof(JATGL_Window));
  window->next = s_JATGL.windowListHead;
  s_JATGL.windowListHead = window;

  if(!CreateNativeWindow(window, width, height, title))
  {
    JATGL_DeleteWindow((JATGLwindow *)window);
    return NULL;
  }

  CreateContextNSGL(window);

  return (JATGLwindow *)window;
}

void JATGL_DeleteWindow(JATGLwindow *handle)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  if(window == NULL)
    return;

  window->characterCallback = NULL;
  window->mouseButtonCallback = NULL;

  assert(s_JATGL.threadContext.allocated == JATGL_TRUE);
  if(window == pthread_getspecific(s_JATGL.threadContext.key))
    MakeContextCurrent(NULL);

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

  JATGL_Window **prev = &s_JATGL.windowListHead;
  while(*prev != window)
    prev = &((*prev)->next);

  *prev = window->next;

  free(window);
}
