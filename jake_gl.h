#ifndef __JAKE_GL_H
#define __JAKE_GL_H

#ifdef __cplusplus
extern "C" {
#endif

#define JATGL_TRUE 1
#define JATGL_FALSE 0
#define JATGL_RELEASE 0
#define JATGL_PRESS 1

#define JATGL_KEY_UNKNOWN -1

#define JATGL_KEY_B 66
#define JATGL_KEY_C 67
#define JATGL_KEY_E 69
#define JATGL_KEY_R 82
#define JATGL_KEY_V 86
#define JATGL_KEY_X 88
#define JATGL_KEY_Z 90

#define JATGL_KEY_ENTER 257
#define JATGL_KEY_TAB 258
#define JATGL_KEY_BACKSPACE 259
#define JATGL_KEY_DELETE 261
#define JATGL_KEY_RIGHT 262
#define JATGL_KEY_LEFT 263
#define JATGL_KEY_DOWN 264
#define JATGL_KEY_UP 265
#define JATGL_KEY_PAGE_UP 266
#define JATGL_KEY_PAGE_DOWN 267
#define JATGL_KEY_HOME 268
#define JATGL_KEY_END 269

#define JATGL_KEY_LEFT_SHIFT 340
#define JATGL_KEY_LEFT_CONTROL 341
#define JATGL_KEY_RIGHT_SHIFT 344
#define JATGL_KEY_RIGHT_CONTROL 345

#define JATGL_KEY_FIRST JATGL_KEY_B
#define JATGL_KEY_LAST JATGL_KEY_RIGHT_CONTROL

#define JATGL_MOUSE_BUTTON_LEFT 0
#define JATGL_MOUSE_BUTTON_RIGHT 1
#define JATGL_MOUSE_BUTTON_MIDDLE 2

typedef struct JATGLwindow JATGLwindow;
typedef void (*JATGLMouseButtonCallback)(JATGLwindow *, int, int, int);
typedef void (*JATGLCharacterCallback)(JATGLwindow *, unsigned int);

int JATGL_Initialize(void);
void JATGL_Shutdown(void);
void JATGL_GetFrameBufferSize(JATGLwindow *window, int *width, int *height);
JATGLwindow *JATGL_NewWindow(int width, int height, const char *title);
void JATGL_DeleteWindow(JATGLwindow *window);
int JATGL_WindowShouldClose(JATGLwindow *window);
void JATGL_GetWindowSize(JATGLwindow *window, int *width, int *height);
void JATGL_SwapBuffers(JATGLwindow *window);
void JATGL_Poll(void);

void JATGL_GetMousePosition(JATGLwindow *handle, double *xpos, double *ypos);
double JATGL_GetTime(void);
void JATGL_SetCharacterCallback(JATGLwindow *window, JATGLCharacterCallback callback);
void JATGL_SetMouseButtonCallback(JATGLwindow *window, JATGLMouseButtonCallback callback);
int JATGL_GetKeyState(JATGLwindow *window, int key);
int JATGL_GetMouseButtonState(JATGLwindow *window, int button);

#ifdef __cplusplus
}
#endif

#endif    // #ifndef __JAKE_GL_H