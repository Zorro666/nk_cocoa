#include "apple_cocoa.h"

#include <OpenGL/gl3.h>
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

static const char *vertex_shader_text =
    "#version 330\n"
    "void main()\n"
    "{\n"
    "    const vec4 verts[4] = vec4[4](vec4(-1.0, -1.0, 0.0, 1.0), vec4(1.0, -1.0, 0.0, 1.0),\n"
    "                          vec4(-1.0, 1.0, 0.0, 1.0), vec4(1.0, 1.0, 0.0, 1.0));\n"
    "    gl_Position = verts[gl_VertexID];\n"
    "}\n";

static const char *fragment_shader_text =
    "#version 330\n"
    "out vec4 fragment;\n"
    "void main()\n"
    "{\n"
    "    const float grid = 64.0;"
    "    vec2 RectRelativePos = gl_FragCoord.xy;\n"
    "    vec2 ab = mod(RectRelativePos.xy, vec2(grid * 2.0));\n"
    "    bool checkerVariant =\n"
    "         ((ab.x < grid && ab.y < grid) ||\n"
    "          (ab.x > grid && ab.y > grid));\n"
    "    fragment = checkerVariant ? vec4(1,0,0,1) : vec4(0,1,0,1);\n"
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

  COCOAwindow *window = COCOA_NewWindow(640, 480, "OpenGL Checkerboard");
  if(!window)
  {
    COCOA_Shutdown();
    exit(EXIT_FAILURE);
  }
  COCOAcontext *context = COCOA_NewGLContext(window);
  COCOA_SetGLContext(window, context);
  COCOA_SetKeyCallback(window, KeyCallback);

  GLint status;

  const GLuint vertex_shader = glCreateShader(GL_VERTEX_SHADER);
  glShaderSource(vertex_shader, 1, &vertex_shader_text, NULL);
  glCompileShader(vertex_shader);
  glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, &status);
  if(status != GL_TRUE)
  {
    int length;
    char buffer[4096];
    glGetShaderInfoLog(vertex_shader, 4096, &length, buffer);
    buffer[length] = '\0';
    fprintf(stderr, "%s\n", buffer);
  }
  assert(status == GL_TRUE);

  const GLuint fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
  glShaderSource(fragment_shader, 1, &fragment_shader_text, NULL);
  glCompileShader(fragment_shader);
  glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, &status);
  if(status != GL_TRUE)
  {
    int length;
    char buffer[4096];
    glGetShaderInfoLog(fragment_shader, 4096, &length, buffer);
    buffer[length] = '\0';
    fprintf(stderr, "%s\n", buffer);
  }
  assert(status == GL_TRUE);

  const GLuint program = glCreateProgram();
  glAttachShader(program, vertex_shader);
  glAttachShader(program, fragment_shader);
  glLinkProgram(program);

  GLuint vertex_array;
  glGenVertexArrays(1, &vertex_array);
  glBindVertexArray(vertex_array);

  while(!COCOA_WindowShouldClose(window) && !closeWindow)
  {
    int width, height;

    COCOA_GetFrameBufferSize(window, &width, &height);

    glViewport(0, 0, width, height);
    glClear(GL_COLOR_BUFFER_BIT);

    glDisable(GL_DEPTH_TEST);
    glUseProgram(program);
    glBindVertexArray(vertex_array);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    COCOA_SwapBuffers(window);
    COCOA_Poll();
  }

  COCOA_DeleteWindow(window);

  COCOA_Shutdown();
  exit(EXIT_SUCCESS);
}

//! [code]
