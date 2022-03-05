#include "apple_cocoa.h"

#include <OpenGL/gl3.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <cmath>

static inline void rotate_Z(float *M, float angle)
{
  float s = sinf(angle);
  float c = cosf(angle);
  M[0 * 4 + 0] = c;
  M[0 * 4 + 1] = s;
  M[0 * 4 + 2] = 0.0f;
  M[0 * 4 + 3] = 0.0f;
  M[1 * 4 + 0] = -s;
  M[1 * 4 + 1] = c;
  M[1 * 4 + 2] = 0.0f;
  M[1 * 4 + 3] = 0.0f;
  M[2 * 4 + 0] = 0.0f;
  M[2 * 4 + 1] = 0.0f;
  M[2 * 4 + 2] = 1.0f;
  M[2 * 4 + 3] = 0.0f;
  M[3 * 4 + 0] = 0.0f;
  M[3 * 4 + 1] = 0.0f;
  M[3 * 4 + 2] = 0.0f;
  M[3 * 4 + 3] = 1.0f;
}

static const struct
{
  float x, y;
  float r, g, b;
} vertices[3] = {{-0.6f, -0.4f, 1.f, 0.f, 0.f},
                 {0.6f, -0.4f, 0.f, 1.f, 0.f},
                 {0.f, 0.6f, 0.f, 0.f, 1.f}};

static const char *vertex_shader_text =
    "#version 330\n"
    "uniform mat4 MVP;\n"
    "in vec3 vCol;\n"
    "in vec2 vPos;\n"
    "out vec3 color;\n"
    "void main()\n"
    "{\n"
    "    gl_Position = MVP * vec4(vPos, 0.0, 1.0);\n"
    "    color = vCol;\n"
    "}\n";

static const char *fragment_shader_text =
    "#version 330\n"
    "in vec3 color;\n"
    "out vec4 fragment;\n"
    "void main()\n"
    "{\n"
    "    fragment = vec4(color, 1.0);\n"
    "}\n";

static int closeWindow = 0;
void KeyCallback(COCOAwindow *window, int key, int action)
{
  if((key == COCOA_KEY_ESCAPE) && (action = COCOA_PRESS))
  {
    closeWindow = 1;
  }
}

int main(void)
{
  if(!COCOA_Initialize())
    exit(EXIT_FAILURE);

  COCOAwindow *window = COCOA_NewWindow(640, 480, "Simple OpenGL Triangle");
  if(!window)
  {
    COCOA_Shutdown();
    exit(EXIT_FAILURE);
  }
  COCOAcontext *context = COCOA_NewGLContext(window);
  COCOA_SetGLContext(window, context);
  COCOA_SetKeyCallback(window, KeyCallback);

  GLuint vertex_buffer;
  glGenBuffers(1, &vertex_buffer);
  glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

  const GLuint vertex_shader = glCreateShader(GL_VERTEX_SHADER);
  glShaderSource(vertex_shader, 1, &vertex_shader_text, NULL);
  glCompileShader(vertex_shader);

  const GLuint fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
  glShaderSource(fragment_shader, 1, &fragment_shader_text, NULL);

  glCompileShader(fragment_shader);

  const GLuint program = glCreateProgram();
  glAttachShader(program, vertex_shader);
  glAttachShader(program, fragment_shader);
  glLinkProgram(program);

  const GLint mvp_location = glGetUniformLocation(program, "MVP");
  const GLint vpos_location = glGetAttribLocation(program, "vPos");
  const GLint vcol_location = glGetAttribLocation(program, "vCol");

  GLuint vertex_array;
  glGenVertexArrays(1, &vertex_array);
  glBindVertexArray(vertex_array);
  glEnableVertexAttribArray(vpos_location);
  glVertexAttribPointer(vpos_location, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 5, (void *)0);
  glEnableVertexAttribArray(vcol_location);
  glVertexAttribPointer(vcol_location, 3, GL_FLOAT, GL_FALSE, sizeof(float) * 5,
                        (void *)(sizeof(float) * 2));
  while(!COCOA_WindowShouldClose(window) && !closeWindow)
  {
    int width, height;
    float mvp[16];

    COCOA_GetFrameBufferSize(window, &width, &height);

    glViewport(0, 0, width, height);
    glClear(GL_COLOR_BUFFER_BIT);

    rotate_Z(mvp, (float)COCOA_GetTime());

    glUseProgram(program);
    glUniformMatrix4fv(mvp_location, 1, GL_FALSE, (const GLfloat *)&mvp);
    glBindVertexArray(vertex_array);
    glDrawArrays(GL_TRIANGLES, 0, 3);

    COCOA_SwapBuffers(window);
    COCOA_Poll();
  }

  COCOA_DeleteWindow(window);

  COCOA_Shutdown();
  exit(EXIT_SUCCESS);
}

//! [code]
