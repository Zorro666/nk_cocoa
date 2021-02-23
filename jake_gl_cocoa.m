#include "jake_gl.h"

#include <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#include <mach/mach_time.h>
#include <pthread.h>

typedef struct JATGL_Window
{
  struct JATGL_Window *next;
  id nsglPixelFormat;
  id nsglObject;
  id nsWindow;
  id delegate;
  id view;
  int shouldClose;
  char mouseButtons[3];
  char keys[JATGL_KEY_LAST + 1];

  JATGLCharacterCallback characterCallback;
  JATGLKeyCallback keyCallback;
  JATGLMouseButtonCallback mouseButtonCallback;
  JATGLScrollCallback scrollCallback;
} JATGL_Window;

typedef struct JATGL_GlobalState
{
  short int keycodes[256];
  pthread_key_t contextTLSkey;
  int contextTLSAllocated;
  JATGL_Window *windowListHead;
  CGEventSourceRef eventSource;
  id nsAppDelegate;
  id keyUpMonitor;
  uint64_t timerFrequency;
} JATGL_GlobalState;

static JATGL_GlobalState s_JATGL = {0};

static void MakeContextCurrent(JATGL_Window *window)
{
  @autoreleasepool
  {
    if(window)
      [window->nsglObject makeCurrentContext];
    else
      [NSOpenGLContext clearCurrentContext];

    assert(s_JATGL.contextTLSAllocated);
    pthread_setspecific(s_JATGL.contextTLSkey, window);
  }
}

static void CreateKeyTables(void)
{
  memset(s_JATGL.keycodes, -1, sizeof(s_JATGL.keycodes));

  s_JATGL.keycodes[0x1D] = JATGL_KEY_0;
  s_JATGL.keycodes[0x12] = JATGL_KEY_1;
  s_JATGL.keycodes[0x13] = JATGL_KEY_2;
  s_JATGL.keycodes[0x14] = JATGL_KEY_3;
  s_JATGL.keycodes[0x15] = JATGL_KEY_4;
  s_JATGL.keycodes[0x17] = JATGL_KEY_5;
  s_JATGL.keycodes[0x16] = JATGL_KEY_6;
  s_JATGL.keycodes[0x1A] = JATGL_KEY_7;
  s_JATGL.keycodes[0x1C] = JATGL_KEY_8;
  s_JATGL.keycodes[0x19] = JATGL_KEY_9;

  s_JATGL.keycodes[0x00] = JATGL_KEY_A;
  s_JATGL.keycodes[0x0B] = JATGL_KEY_B;
  s_JATGL.keycodes[0x08] = JATGL_KEY_C;
  s_JATGL.keycodes[0x02] = JATGL_KEY_D;
  s_JATGL.keycodes[0x0E] = JATGL_KEY_E;
  s_JATGL.keycodes[0x03] = JATGL_KEY_F;
  s_JATGL.keycodes[0x05] = JATGL_KEY_G;
  s_JATGL.keycodes[0x04] = JATGL_KEY_H;
  s_JATGL.keycodes[0x22] = JATGL_KEY_I;
  s_JATGL.keycodes[0x26] = JATGL_KEY_J;
  s_JATGL.keycodes[0x28] = JATGL_KEY_K;
  s_JATGL.keycodes[0x25] = JATGL_KEY_L;
  s_JATGL.keycodes[0x2E] = JATGL_KEY_M;
  s_JATGL.keycodes[0x2D] = JATGL_KEY_N;
  s_JATGL.keycodes[0x1F] = JATGL_KEY_O;
  s_JATGL.keycodes[0x23] = JATGL_KEY_P;
  s_JATGL.keycodes[0x0C] = JATGL_KEY_Q;
  s_JATGL.keycodes[0x0F] = JATGL_KEY_R;
  s_JATGL.keycodes[0x01] = JATGL_KEY_S;
  s_JATGL.keycodes[0x11] = JATGL_KEY_T;
  s_JATGL.keycodes[0x20] = JATGL_KEY_U;
  s_JATGL.keycodes[0x09] = JATGL_KEY_V;
  s_JATGL.keycodes[0x0D] = JATGL_KEY_W;
  s_JATGL.keycodes[0x07] = JATGL_KEY_X;
  s_JATGL.keycodes[0x10] = JATGL_KEY_Y;
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

  s_JATGL.keycodes[0x27] = JATGL_KEY_APOSTROPHE;
  s_JATGL.keycodes[0x2A] = JATGL_KEY_BACKSLASH;
  s_JATGL.keycodes[0x2B] = JATGL_KEY_COMMA;
  s_JATGL.keycodes[0x18] = JATGL_KEY_EQUAL;
  s_JATGL.keycodes[0x32] = JATGL_KEY_GRAVE_ACCENT;
  s_JATGL.keycodes[0x21] = JATGL_KEY_LEFT_BRACKET;
  s_JATGL.keycodes[0x1B] = JATGL_KEY_MINUS;
  s_JATGL.keycodes[0x2F] = JATGL_KEY_PERIOD;
  s_JATGL.keycodes[0x1E] = JATGL_KEY_RIGHT_BRACKET;
  s_JATGL.keycodes[0x29] = JATGL_KEY_SEMICOLON;
  s_JATGL.keycodes[0x2C] = JATGL_KEY_SLASH;

  s_JATGL.keycodes[0x33] = JATGL_KEY_BACKSPACE;
  s_JATGL.keycodes[0x75] = JATGL_KEY_DELETE;
  s_JATGL.keycodes[0x7D] = JATGL_KEY_DOWN;
  s_JATGL.keycodes[0x77] = JATGL_KEY_END;
  s_JATGL.keycodes[0x24] = JATGL_KEY_ENTER;
  s_JATGL.keycodes[0x35] = JATGL_KEY_ESCAPE;
  s_JATGL.keycodes[0x73] = JATGL_KEY_HOME;
  s_JATGL.keycodes[0x72] = JATGL_KEY_INSERT;
  s_JATGL.keycodes[0x7B] = JATGL_KEY_LEFT;
  s_JATGL.keycodes[0x3B] = JATGL_KEY_LEFT_CONTROL;
  s_JATGL.keycodes[0x38] = JATGL_KEY_LEFT_SHIFT;
  s_JATGL.keycodes[0x79] = JATGL_KEY_PAGE_DOWN;
  s_JATGL.keycodes[0x74] = JATGL_KEY_PAGE_UP;
  s_JATGL.keycodes[0x7C] = JATGL_KEY_RIGHT;
  s_JATGL.keycodes[0x3E] = JATGL_KEY_RIGHT_CONTROL;
  s_JATGL.keycodes[0x3C] = JATGL_KEY_RIGHT_SHIFT;
  s_JATGL.keycodes[0x31] = JATGL_KEY_SPACE;
  s_JATGL.keycodes[0x30] = JATGL_KEY_TAB;
  s_JATGL.keycodes[0x7E] = JATGL_KEY_UP;
}

static int TranslateKey(unsigned int key)
{
  if(key >= sizeof(s_JATGL.keycodes) / sizeof(s_JATGL.keycodes[0]))
    return JATGL_KEY_UNKNOWN;

  return s_JATGL.keycodes[key];
}

static void InputMouseClick(JATGL_Window *window, int button, int action)
{
  if(button < 0 || button > 2)
    return;

  window->mouseButtons[button] = (char)action;
  if(window->mouseButtonCallback)
    window->mouseButtonCallback((JATGLwindow *)window, button, action, 0);
}

static void InputKey(JATGL_Window *window, int key, int action)
{
  if(key >= 0 && key <= JATGL_KEY_LAST)
  {
    if(action == JATGL_RELEASE && window->keys[key] == JATGL_RELEASE)
      return;

    window->keys[key] = (char)action;
  }
}

void JATGL_SwapBuffers(JATGLwindow *handle)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  @autoreleasepool
  {
    [window->nsglObject flushBuffer];
  }
}

@interface JATGL_WindowDelegate : NSObject
{
  JATGL_Window *window;
}

- (instancetype)initWithJATGLWindow:(JATGL_Window *)initWindow;

@end

@implementation JATGL_WindowDelegate

- (instancetype)initWithJATGLWindow:(JATGL_Window *)initWindow
{
  self = [super init];
  assert(self);
  window = initWindow;
  return self;
}

- (BOOL)windowShouldClose:(id)sender
{
  window->shouldClose = JATGL_TRUE;
  return NO;
}
@end

@interface JATGL_WindowView : NSView<NSTextInputClient>

{
  JATGL_Window *window;
}

- (instancetype)initWithJATGLWindow:(JATGL_Window *)initWindow;

@end

@implementation JATGL_WindowView

- (instancetype)initWithJATGLWindow:(JATGL_Window *)initWindow
{
  self = [super init];
  assert(self);
  window = initWindow;
  return self;
}

- (void)updateLayer
{
  [window->nsglObject update];
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

- (void)keyDown:(NSEvent *)event
{
  const int key = TranslateKey([event keyCode]);
  InputKey(window, key, JATGL_PRESS);
  [self interpretKeyEvents:@[ event ]];
  if(window->keyCallback)
    window->keyCallback((JATGLwindow *)window, key, JATGL_PRESS);
}

- (void)flagsChanged:(NSEvent *)event
{
  int action;
  const unsigned int modifierFlags =
      [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
  const int key = TranslateKey([event keyCode]);
  NSUInteger keyFlag = 0;
  switch(key)
  {
    case JATGL_KEY_LEFT_SHIFT:
    case JATGL_KEY_RIGHT_SHIFT: keyFlag = NSEventModifierFlagShift; break;
    case JATGL_KEY_LEFT_CONTROL:
    case JATGL_KEY_RIGHT_CONTROL: keyFlag = NSEventModifierFlagControl; break;
  }

  if(keyFlag & modifierFlags)
  {
    if(window->keys[key] == JATGL_PRESS)
      action = JATGL_RELEASE;
    else
      action = JATGL_PRESS;
  }
  else
    action = JATGL_RELEASE;

  InputKey(window, key, action);
}

- (void)keyUp:(NSEvent *)event
{
  const int key = TranslateKey([event keyCode]);
  InputKey(window, key, JATGL_RELEASE);
  if(window->keyCallback)
    window->keyCallback((JATGLwindow *)window, key, JATGL_RELEASE);
}

- (void)scrollWheel:(NSEvent *)event
{
  double deltaX = [event scrollingDeltaX];
  double deltaY = [event scrollingDeltaY];

  if([event hasPreciseScrollingDeltas])
  {
    deltaX *= 0.1;
    deltaY *= 0.1;
  }

  if(fabs(deltaX) > 0.0 || fabs(deltaY) > 0.0)
  {
    if(window->scrollCallback)
      window->scrollCallback((JATGLwindow *)window, deltaX, deltaY);
  }
}

static const NSRange s_NSRange_Empty = {NSNotFound, 0};

- (BOOL)hasMarkedText
{
  return NO;
}

- (NSRange)markedRange
{
  return s_NSRange_Empty;
}

- (NSRange)selectedRange
{
  return s_NSRange_Empty;
}

- (void)setMarkedText:(id)string
        selectedRange:(NSRange)selectedRange
     replacementRange:(NSRange)replacementRange
{
}

- (void)unmarkText
{
}

- (NSArray *)validAttributesForMarkedText
{
  return [NSArray array];
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
                                                actualRange:(NSRangePointer)actualRange
{
  return nil;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
  return 0;
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange
{
  const NSRect frame = [window->view frame];
  return NSMakeRect(frame.origin.x, frame.origin.y, 0.0, 0.0);
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
  if(!window->characterCallback)
    return;

  NSString *characters;
  NSEvent *event = [NSApp currentEvent];

  if([string isKindOfClass:[NSAttributedString class]])
    characters = [string string];
  else
    characters = (NSString *)string;

  NSRange range = NSMakeRange(0, [characters length]);
  while(range.length)
  {
    uint32_t codepoint = 0;

    if([characters getBytes:&codepoint
                  maxLength:sizeof(codepoint)
                 usedLength:NULL
                   encoding:NSUTF32StringEncoding
                    options:0
                      range:range
             remainingRange:&range])
    {
      if(codepoint >= 0xf700 && codepoint <= 0xf7ff)
        continue;

      if(window->characterCallback)
        window->characterCallback((JATGLwindow *)window, codepoint);
    }
  }
}

@end

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
    const NSPoint pos = [window->nsWindow mouseLocationOutsideOfEventStream];

    if(xpos)
      *xpos = pos.x;
    if(ypos)
      *ypos = contentRect.size.height - pos.y;
  }
}

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
    [window->nsglObject update];
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

void JATGL_SetKeyCallback(JATGLwindow *handle, JATGLKeyCallback callback)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  window->keyCallback = callback;
}

void JATGL_SetScrollCallback(JATGLwindow *handle, JATGLScrollCallback callback)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  window->scrollCallback = callback;
}

void JATGL_SetMouseButtonCallback(JATGLwindow *handle, JATGLMouseButtonCallback callback)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  assert(window);
  window->mouseButtonCallback = callback;
}

double JATGL_GetTime(void)
{
  return (double)mach_absolute_time() / s_JATGL.timerFrequency;
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
  memset(&s_JATGL, 0, sizeof(s_JATGL));

  @autoreleasepool
  {
    [NSApplication sharedApplication];

    s_JATGL.nsAppDelegate = [[JATGL_ApplicationDelegate alloc] init];
    assert(s_JATGL.nsAppDelegate);

    [NSApp setDelegate:s_JATGL.nsAppDelegate];

    NSEvent * (^block)(NSEvent *) = ^NSEvent *(NSEvent *event)
    {
      if([event modifierFlags] & NSEventModifierFlagCommand)
        [[NSApp keyWindow] sendEvent:event];
      return event;
    };

    s_JATGL.keyUpMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp handler:block];

    CreateKeyTables();

    s_JATGL.eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if(!s_JATGL.eventSource)
    {
      JATGL_Shutdown();
      return JATGL_FALSE;
    }

    CGEventSourceSetLocalEventsSuppressionInterval(s_JATGL.eventSource, 0.0);

    if(![[NSRunningApplication currentApplication] isFinishedLaunching])
      [NSApp run];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  }

  mach_timebase_info_data_t info;
  mach_timebase_info(&info);
  s_JATGL.timerFrequency = (info.denom * 1e9) / info.numer;

  assert(!s_JATGL.contextTLSAllocated);
  int result = pthread_key_create(&s_JATGL.contextTLSkey, NULL);
  assert(result == 0);
  s_JATGL.contextTLSAllocated = 1;

  return JATGL_TRUE;
}

void JATGL_Shutdown(void)
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

    if(s_JATGL.nsAppDelegate)
    {
      [NSApp setDelegate:nil];
      [s_JATGL.nsAppDelegate release];
      s_JATGL.nsAppDelegate = nil;
    }

    if(s_JATGL.keyUpMonitor)
      [NSEvent removeMonitor:s_JATGL.keyUpMonitor];
  }

  if(s_JATGL.contextTLSAllocated)
    pthread_key_delete(s_JATGL.contextTLSkey);

  memset(&s_JATGL, 0, sizeof(s_JATGL));
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

  window->delegate = [[JATGL_WindowDelegate alloc] initWithJATGLWindow:window];
  assert(window->delegate);

  NSRect contentRect;

  contentRect = NSMakeRect(0, 0, width, height);

  window->nsWindow =
      [[NSWindow alloc] initWithContentRect:contentRect
                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                    backing:NSBackingStoreBuffered
                                      defer:NO];

  assert(window->nsWindow);

  [(NSWindow *)window->nsWindow center];

  window->view = [[JATGL_WindowView alloc] initWithJATGLWindow:window];

  [window->nsWindow setContentView:window->view];
  [window->nsWindow makeFirstResponder:window->view];
  [window->nsWindow setTitle:@(title)];
  [window->nsWindow setDelegate:window->delegate];
  [window->nsWindow setAcceptsMouseMovedEvents:YES];
  [window->nsWindow setRestorable:NO];

  if([window->nsWindow respondsToSelector:@selector(setTabbingMode:)])
    [window->nsWindow setTabbingMode:NSWindowTabbingModeDisallowed];

  NSOpenGLPixelFormatAttribute attributes[16] = {NSOpenGLPFAAccelerated,
                                                 NSOpenGLPFAClosestPolicy,
                                                 NSOpenGLPFAOpenGLProfile,
                                                 NSOpenGLProfileVersion4_1Core,
                                                 NSOpenGLPFAColorSize,
                                                 24,
                                                 NSOpenGLPFAAlphaSize,
                                                 8,
                                                 NSOpenGLPFADepthSize,
                                                 24,
                                                 NSOpenGLPFAStencilSize,
                                                 8,
                                                 NSOpenGLPFADoubleBuffer,
                                                 NSOpenGLPFASampleBuffers,
                                                 0,
                                                 0};

  window->nsglPixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
  assert(window->nsglPixelFormat);

  window->nsglObject =
      [[NSOpenGLContext alloc] initWithFormat:window->nsglPixelFormat shareContext:nil];
  assert(window->nsglObject);

  [window->view setWantsBestResolutionOpenGLSurface:true];
  [window->nsglObject setView:window->view];

  [window->nsWindow orderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  [window->nsWindow makeKeyAndOrderFront:nil];

  MakeContextCurrent(window);

  return (JATGLwindow *)window;
}

void JATGL_DeleteWindow(JATGLwindow *handle)
{
  JATGL_Window *window = (JATGL_Window *)handle;
  if(window == NULL)
    return;

  window->characterCallback = NULL;
  window->keyCallback = NULL;
  window->mouseButtonCallback = NULL;
  window->scrollCallback = NULL;

  assert(s_JATGL.contextTLSAllocated);
  if(window == pthread_getspecific(s_JATGL.contextTLSkey))
    MakeContextCurrent(NULL);

  @autoreleasepool
  {
    [window->nsWindow orderOut:nil];
    [window->nsglPixelFormat release];
    window->nsglPixelFormat = nil;

    [window->nsglObject release];
    window->nsglObject = nil;

    [window->nsWindow setDelegate:nil];
    [window->delegate release];
    window->delegate = nil;

    [window->view release];
    window->view = nil;

    [window->nsWindow close];
    window->nsWindow = nil;

    JATGL_Poll();
  }

  JATGL_Window **prev = &s_JATGL.windowListHead;
  while(*prev != window)
    prev = &((*prev)->next);

  *prev = window->next;

  free(window);
}
