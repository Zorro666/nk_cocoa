#ifndef JAKE_GL_H
#define JAKE_GL_H

#ifdef __cplusplus
extern "C" {
#endif

#define JATGL_TRUE                   1
#define JATGL_FALSE                  0
#define JATGL_RELEASE                0
#define JATGL_PRESS                  1

#define JATGL_KEY_UNKNOWN            -1

#define JATGL_KEY_B                  66
#define JATGL_KEY_C                  67
#define JATGL_KEY_E                  69
#define JATGL_KEY_R                  82
#define JATGL_KEY_V                  86
#define JATGL_KEY_X                  88
#define JATGL_KEY_Z                  90

#define JATGL_KEY_ENTER              257
#define JATGL_KEY_TAB                258
#define JATGL_KEY_BACKSPACE          259
#define JATGL_KEY_DELETE             261
#define JATGL_KEY_RIGHT              262
#define JATGL_KEY_LEFT               263
#define JATGL_KEY_DOWN               264
#define JATGL_KEY_UP                 265
#define JATGL_KEY_PAGE_UP            266
#define JATGL_KEY_PAGE_DOWN          267
#define JATGL_KEY_HOME               268
#define JATGL_KEY_END                269

#define JATGL_KEY_LEFT_SHIFT         340
#define JATGL_KEY_LEFT_CONTROL       341
#define JATGL_KEY_RIGHT_SHIFT        344
#define JATGL_KEY_RIGHT_CONTROL      345

#define JATGL_KEY_FIRST              JATGL_KEY_B
#define JATGL_KEY_LAST               JATGL_KEY_RIGHT_CONTROL

#define JATGL_MOUSE_BUTTON_LEFT      0
#define JATGL_MOUSE_BUTTON_RIGHT     1
#define JATGL_MOUSE_BUTTON_MIDDLE    2

typedef void (*JATGLglproc)(void);
typedef struct JATGLwindow JATGLwindow;
typedef void (*JATGLmouse_button_function)(JATGLwindow*,int,int,int);
typedef void (*JATGLcharacter_function)(JATGLwindow*,unsigned int);

void JATGL_MakeContextCurrent(JATGLwindow* window);
void JATGL_DeleteWindow(JATGLwindow* window);
int JATGL_Initialize(void);
JATGLwindow* JATGL_NewWindow(int width, int height, const char* title);
void JATGL_Shutdown(void);
JATGLglproc JATGL_GetGLProcAddress(const char* procname);
int JATGL_WindowShouldClose(JATGLwindow* window);
void JATGL_GetFrameBufferSize(JATGLwindow* window, int* width, int* height);
void JATGL_SwapBuffers(JATGLwindow* window);
void JATGL_Poll(void);

void JATGL_GetMousePosition(JATGLwindow* handle, double* xpos, double* ypos);
double JATGL_GetTime(void);
JATGLcharacter_function JATGL_SetCharacterCallback(JATGLwindow* window, JATGLcharacter_function callback);
JATGLmouse_button_function JATGL_SetMouseButtonCallback(JATGLwindow* window, JATGLmouse_button_function callback);
void JATGL_GetWindowSize(JATGLwindow* window, int* width, int* height);
int JATGL_GetKeyState(JATGLwindow* window, int key);
int JATGL_GetMouseButtonState(JATGLwindow* window, int button);

#ifdef __cplusplus
}
#endif

#endif // #ifndef JAKE_GL_H