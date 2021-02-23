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

#define JATGL_KEY_SPACE 32
#define JATGL_KEY_APOSTROPHE 39
#define JATGL_KEY_COMMA 44
#define JATGL_KEY_MINUS 45
#define JATGL_KEY_PERIOD 46
#define JATGL_KEY_SLASH 47

#define JATGL_KEY_0 48
#define JATGL_KEY_1 49
#define JATGL_KEY_2 50
#define JATGL_KEY_3 51
#define JATGL_KEY_4 52
#define JATGL_KEY_5 53
#define JATGL_KEY_6 54
#define JATGL_KEY_7 55
#define JATGL_KEY_8 56
#define JATGL_KEY_9 57

#define JATGL_KEY_SEMICOLON 59
#define JATGL_KEY_EQUAL 61

#define JATGL_KEY_A 65
#define JATGL_KEY_B 66
#define JATGL_KEY_C 67
#define JATGL_KEY_D 68
#define JATGL_KEY_E 69
#define JATGL_KEY_F 70
#define JATGL_KEY_G 71
#define JATGL_KEY_H 72
#define JATGL_KEY_I 73
#define JATGL_KEY_J 74
#define JATGL_KEY_K 75
#define JATGL_KEY_L 76
#define JATGL_KEY_M 77
#define JATGL_KEY_N 78
#define JATGL_KEY_O 79
#define JATGL_KEY_P 80
#define JATGL_KEY_Q 81
#define JATGL_KEY_R 82
#define JATGL_KEY_S 83
#define JATGL_KEY_T 84
#define JATGL_KEY_U 85
#define JATGL_KEY_V 86
#define JATGL_KEY_W 87
#define JATGL_KEY_X 88
#define JATGL_KEY_Y 89
#define JATGL_KEY_Z 90

#define JATGL_KEY_LEFT_BRACKET 91
#define JATGL_KEY_BACKSLASH 92
#define JATGL_KEY_RIGHT_BRACKET 93
#define JATGL_KEY_GRAVE_ACCENT 96

#define JATGL_KEY_ESCAPE 300
#define JATGL_KEY_ENTER 301
#define JATGL_KEY_TAB 302
#define JATGL_KEY_BACKSPACE 303
#define JATGL_KEY_INSERT 304
#define JATGL_KEY_DELETE 305
#define JATGL_KEY_RIGHT 306
#define JATGL_KEY_LEFT 307
#define JATGL_KEY_DOWN 308
#define JATGL_KEY_UP 309
#define JATGL_KEY_PAGE_UP 310
#define JATGL_KEY_PAGE_DOWN 311
#define JATGL_KEY_HOME 312
#define JATGL_KEY_END 313

#define JATGL_KEY_LEFT_SHIFT 400
#define JATGL_KEY_LEFT_CONTROL 401
#define JATGL_KEY_RIGHT_SHIFT 402
#define JATGL_KEY_RIGHT_CONTROL 403

#define JATGL_KEY_FIRST JATGL_KEY_SPACE
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