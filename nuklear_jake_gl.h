/*
 * Nuklear - 1.32.0 - public domain
 * no warrenty implied; use at your own risk.
 * authored from 2015-2016 by Micha Mettke
 */
/*
 * ==============================================================
 *
 *                              API
 *
 * ===============================================================
 */
#ifndef NK_JAKE_GL_H_
#define NK_JAKE_GL_H_

#include <OpenGL/gl3.h>
#include "jake_gl.h"

enum nk_jake_init_state
{
  NK_JAKE_DEFAULT,
  NK_JAKE_INSTALL_CALLBACKS
};

NK_API struct nk_context *nk_jake_init(JATGLwindow *win, enum nk_jake_init_state);
NK_API void nk_jake_shutdown(void);
NK_API void nk_jake_font_stash_begin(struct nk_font_atlas **atlas);
NK_API void nk_jake_font_stash_end(void);
NK_API void nk_jake_new_frame(void);
NK_API void nk_jake_render(enum nk_anti_aliasing, int max_vertex_buffer, int max_element_buffer);

NK_API void nk_jake_device_destroy(void);
NK_API void nk_jake_device_create(void);

NK_API void nk_jake_char_callback(JATGLwindow *win, unsigned int codepoint);
NK_API void nk_jake_scroll_callback(JATGLwindow *win, double xoff, double yoff);
NK_API void nk_jake_mouse_button_callback(JATGLwindow *win, int button, int action, int mods);

#endif
/*
 * ==============================================================
 *
 *                          IMPLEMENTATION
 *
 * ===============================================================
 */
#ifdef NK_JAKE_GL_IMPLEMENTATION

#ifndef NK_JAKE_TEXT_MAX
#define NK_JAKE_TEXT_MAX 256
#endif
#ifndef NK_JAKE_DOUBLE_CLICK_LO
#define NK_JAKE_DOUBLE_CLICK_LO 0.02
#endif
#ifndef NK_JAKE_DOUBLE_CLICK_HI
#define NK_JAKE_DOUBLE_CLICK_HI 0.2
#endif

struct nk_jake_device
{
  struct nk_buffer cmds;
  struct nk_draw_null_texture null;
  GLuint vbo, vao, ebo;
  GLuint prog;
  GLuint vert_shdr;
  GLuint frag_shdr;
  GLint attrib_pos;
  GLint attrib_uv;
  GLint attrib_col;
  GLint uniform_tex;
  GLint uniform_proj;
  GLuint font_tex;
};

struct nk_jake_vertex
{
  float position[2];
  float uv[2];
  nk_byte col[4];
};

static struct nk_jake
{
  JATGLwindow *win;
  int width, height;
  int display_width, display_height;
  struct nk_jake_device ogl;
  struct nk_context ctx;
  struct nk_font_atlas atlas;
  struct nk_vec2 fb_scale;
  unsigned int text[NK_JAKE_TEXT_MAX];
  int text_len;
  struct nk_vec2 scroll;
  double last_button_click;
  int is_double_click_down;
  struct nk_vec2 double_click_pos;
} nk_jake;

#ifdef __APPLE__
#define NK_SHADER_VERSION "#version 150\n"
#else
#define NK_SHADER_VERSION "#version 300 es\n"
#endif

NK_API void nk_jake_device_create(void)
{
  GLint status;
  static const GLchar *vertex_shader = NK_SHADER_VERSION
      "uniform mat4 ProjMtx;\n"
      "in vec2 Position;\n"
      "in vec2 TexCoord;\n"
      "in vec4 Color;\n"
      "out vec2 Frag_UV;\n"
      "out vec4 Frag_Color;\n"
      "void main() {\n"
      "   Frag_UV = TexCoord;\n"
      "   Frag_Color = Color;\n"
      "   gl_Position = ProjMtx * vec4(Position.xy, 0, 1);\n"
      "}\n";
  static const GLchar *fragment_shader = NK_SHADER_VERSION
      "precision mediump float;\n"
      "uniform sampler2D Texture;\n"
      "in vec2 Frag_UV;\n"
      "in vec4 Frag_Color;\n"
      "out vec4 Out_Color;\n"
      "void main(){\n"
      "   Out_Color = Frag_Color * texture(Texture, Frag_UV.st);\n"
      "}\n";

  struct nk_jake_device *dev = &nk_jake.ogl;
  nk_buffer_init_default(&dev->cmds);
  dev->prog = glCreateProgram();
  dev->vert_shdr = glCreateShader(GL_VERTEX_SHADER);
  dev->frag_shdr = glCreateShader(GL_FRAGMENT_SHADER);
  glShaderSource(dev->vert_shdr, 1, &vertex_shader, 0);
  glShaderSource(dev->frag_shdr, 1, &fragment_shader, 0);
  glCompileShader(dev->vert_shdr);
  glCompileShader(dev->frag_shdr);
  glGetShaderiv(dev->vert_shdr, GL_COMPILE_STATUS, &status);
  assert(status == GL_TRUE);
  glGetShaderiv(dev->frag_shdr, GL_COMPILE_STATUS, &status);
  assert(status == GL_TRUE);
  glAttachShader(dev->prog, dev->vert_shdr);
  glAttachShader(dev->prog, dev->frag_shdr);
  glLinkProgram(dev->prog);
  glGetProgramiv(dev->prog, GL_LINK_STATUS, &status);
  assert(status == GL_TRUE);

  dev->uniform_tex = glGetUniformLocation(dev->prog, "Texture");
  dev->uniform_proj = glGetUniformLocation(dev->prog, "ProjMtx");
  dev->attrib_pos = glGetAttribLocation(dev->prog, "Position");
  dev->attrib_uv = glGetAttribLocation(dev->prog, "TexCoord");
  dev->attrib_col = glGetAttribLocation(dev->prog, "Color");

  {
    /* buffer setup */
    GLsizei vs = sizeof(struct nk_jake_vertex);
    size_t vp = offsetof(struct nk_jake_vertex, position);
    size_t vt = offsetof(struct nk_jake_vertex, uv);
    size_t vc = offsetof(struct nk_jake_vertex, col);

    glGenBuffers(1, &dev->vbo);
    glGenBuffers(1, &dev->ebo);
    glGenVertexArrays(1, &dev->vao);

    glBindVertexArray(dev->vao);
    glBindBuffer(GL_ARRAY_BUFFER, dev->vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, dev->ebo);

    glEnableVertexAttribArray((GLuint)dev->attrib_pos);
    glEnableVertexAttribArray((GLuint)dev->attrib_uv);
    glEnableVertexAttribArray((GLuint)dev->attrib_col);

    glVertexAttribPointer((GLuint)dev->attrib_pos, 2, GL_FLOAT, GL_FALSE, vs, (void *)vp);
    glVertexAttribPointer((GLuint)dev->attrib_uv, 2, GL_FLOAT, GL_FALSE, vs, (void *)vt);
    glVertexAttribPointer((GLuint)dev->attrib_col, 4, GL_UNSIGNED_BYTE, GL_TRUE, vs, (void *)vc);
  }

  glBindTexture(GL_TEXTURE_2D, 0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
}

NK_INTERN void nk_jake_device_upload_atlas(const void *image, int width, int height)
{
  struct nk_jake_device *dev = &nk_jake.ogl;
  glGenTextures(1, &dev->font_tex);
  glBindTexture(GL_TEXTURE_2D, dev->font_tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)width, (GLsizei)height, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, image);
}

NK_API void nk_jake_device_destroy(void)
{
  struct nk_jake_device *dev = &nk_jake.ogl;
  glDetachShader(dev->prog, dev->vert_shdr);
  glDetachShader(dev->prog, dev->frag_shdr);
  glDeleteShader(dev->vert_shdr);
  glDeleteShader(dev->frag_shdr);
  glDeleteProgram(dev->prog);
  glDeleteTextures(1, &dev->font_tex);
  glDeleteBuffers(1, &dev->vbo);
  glDeleteBuffers(1, &dev->ebo);
  nk_buffer_free(&dev->cmds);
}

NK_API void nk_jake_render(enum nk_anti_aliasing AA, int max_vertex_buffer, int max_element_buffer)
{
  struct nk_jake_device *dev = &nk_jake.ogl;
  struct nk_buffer vbuf, ebuf;
  GLfloat ortho[4][4] = {
      {2.0f, 0.0f, 0.0f, 0.0f},
      {0.0f, -2.0f, 0.0f, 0.0f},
      {0.0f, 0.0f, -1.0f, 0.0f},
      {-1.0f, 1.0f, 0.0f, 1.0f},
  };
  ortho[0][0] /= (GLfloat)nk_jake.width;
  ortho[1][1] /= (GLfloat)nk_jake.height;

  /* setup global state */
  glEnable(GL_BLEND);
  glBlendEquation(GL_FUNC_ADD);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDisable(GL_CULL_FACE);
  glDisable(GL_DEPTH_TEST);
  glEnable(GL_SCISSOR_TEST);
  glActiveTexture(GL_TEXTURE0);

  /* setup program */
  glUseProgram(dev->prog);
  glUniform1i(dev->uniform_tex, 0);
  glUniformMatrix4fv(dev->uniform_proj, 1, GL_FALSE, &ortho[0][0]);
  glViewport(0, 0, (GLsizei)nk_jake.display_width, (GLsizei)nk_jake.display_height);
  {
    /* convert from command queue into draw list and draw to screen */
    const struct nk_draw_command *cmd;
    void *vertices, *elements;
    const nk_draw_index *offset = NULL;

    /* allocate vertex and element buffer */
    glBindVertexArray(dev->vao);
    glBindBuffer(GL_ARRAY_BUFFER, dev->vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, dev->ebo);

    glBufferData(GL_ARRAY_BUFFER, max_vertex_buffer, NULL, GL_STREAM_DRAW);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, max_element_buffer, NULL, GL_STREAM_DRAW);

    /* load draw vertices & elements directly into vertex + element buffer */
    vertices = glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY);
    elements = glMapBuffer(GL_ELEMENT_ARRAY_BUFFER, GL_WRITE_ONLY);
    {
      /* fill convert configuration */
      struct nk_convert_config config;
      static const struct nk_draw_vertex_layout_element vertex_layout[] = {
          {NK_VERTEX_POSITION, NK_FORMAT_FLOAT, NK_OFFSETOF(struct nk_jake_vertex, position)},
          {NK_VERTEX_TEXCOORD, NK_FORMAT_FLOAT, NK_OFFSETOF(struct nk_jake_vertex, uv)},
          {NK_VERTEX_COLOR, NK_FORMAT_R8G8B8A8, NK_OFFSETOF(struct nk_jake_vertex, col)},
          {NK_VERTEX_LAYOUT_END}};
      NK_MEMSET(&config, 0, sizeof(config));
      config.vertex_layout = vertex_layout;
      config.vertex_size = sizeof(struct nk_jake_vertex);
      config.vertex_alignment = NK_ALIGNOF(struct nk_jake_vertex);
      config.null = dev->null;
      config.circle_segment_count = 22;
      config.curve_segment_count = 22;
      config.arc_segment_count = 22;
      config.global_alpha = 1.0f;
      config.shape_AA = AA;
      config.line_AA = AA;

      /* setup buffers to load vertices and elements */
      nk_buffer_init_fixed(&vbuf, vertices, (size_t)max_vertex_buffer);
      nk_buffer_init_fixed(&ebuf, elements, (size_t)max_element_buffer);
      nk_convert(&nk_jake.ctx, &dev->cmds, &vbuf, &ebuf, &config);
    }
    glUnmapBuffer(GL_ARRAY_BUFFER);
    glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER);

    /* iterate over and execute each draw command */
    nk_draw_foreach(cmd, &nk_jake.ctx, &dev->cmds)
    {
      if(!cmd->elem_count)
        continue;
      glBindTexture(GL_TEXTURE_2D, (GLuint)cmd->texture.id);
      glScissor((GLint)(cmd->clip_rect.x * nk_jake.fb_scale.x),
                (GLint)((nk_jake.height - (GLint)(cmd->clip_rect.y + cmd->clip_rect.h)) *
                        nk_jake.fb_scale.y),
                (GLint)(cmd->clip_rect.w * nk_jake.fb_scale.x),
                (GLint)(cmd->clip_rect.h * nk_jake.fb_scale.y));
      glDrawElements(GL_TRIANGLES, (GLsizei)cmd->elem_count, GL_UNSIGNED_SHORT, offset);
      offset += cmd->elem_count;
    }
    nk_clear(&nk_jake.ctx);
  }

  /* default OpenGL state */
  glUseProgram(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
}

NK_API void nk_jake_char_callback(JATGLwindow *win, unsigned int codepoint)
{
  (void)win;
  if(nk_jake.text_len < NK_JAKE_TEXT_MAX)
    nk_jake.text[nk_jake.text_len++] = codepoint;
}

NK_API void nk_jake_scroll_callback(JATGLwindow *win, double xoff, double yoff)
{
  (void)win;
  (void)xoff;
  nk_jake.scroll.x += (float)xoff;
  nk_jake.scroll.y += (float)yoff;
}

NK_API void nk_jake_mouse_button_callback(JATGLwindow *window, int button, int action, int mods)
{
  double x, y;
  if(button != JATGL_MOUSE_BUTTON_LEFT)
    return;
  JATGL_GetMousePosition(window, &x, &y);
  if(action == JATGL_PRESS)
  {
    double dt = JATGL_GetTime() - nk_jake.last_button_click;
    if(dt > NK_JAKE_DOUBLE_CLICK_LO && dt < NK_JAKE_DOUBLE_CLICK_HI)
    {
      nk_jake.is_double_click_down = nk_true;
      nk_jake.double_click_pos = nk_vec2((float)x, (float)y);
    }
    nk_jake.last_button_click = JATGL_GetTime();
  }
  else
    nk_jake.is_double_click_down = nk_false;
}

NK_API struct nk_context *nk_jake_init(JATGLwindow *win, enum nk_jake_init_state init_state)
{
  nk_jake.win = win;
  if(init_state == NK_JAKE_INSTALL_CALLBACKS)
  {
    JATGL_SetCharacterCallback(win, nk_jake_char_callback);
    JATGL_SetScrollCallback(win, nk_jake_scroll_callback);
    JATGL_SetMouseButtonCallback(win, nk_jake_mouse_button_callback);
  }
  nk_init_default(&nk_jake.ctx, 0);
  nk_jake.ctx.clip.userdata = nk_handle_ptr(0);
  nk_jake.last_button_click = 0;
  nk_jake_device_create();

  nk_jake.is_double_click_down = nk_false;
  nk_jake.double_click_pos = nk_vec2(0, 0);

  return &nk_jake.ctx;
}

NK_API void nk_jake_font_stash_begin(struct nk_font_atlas **atlas)
{
  nk_font_atlas_init_default(&nk_jake.atlas);
  nk_font_atlas_begin(&nk_jake.atlas);
  *atlas = &nk_jake.atlas;
}

NK_API void nk_jake_font_stash_end(void)
{
  const void *image;
  int w, h;
  image = nk_font_atlas_bake(&nk_jake.atlas, &w, &h, NK_FONT_ATLAS_RGBA32);
  nk_jake_device_upload_atlas(image, w, h);
  nk_font_atlas_end(&nk_jake.atlas, nk_handle_id((int)nk_jake.ogl.font_tex), &nk_jake.ogl.null);
  if(nk_jake.atlas.default_font)
    nk_style_set_font(&nk_jake.ctx, &nk_jake.atlas.default_font->handle);
}

NK_API void nk_jake_new_frame(void)
{
  int i;
  double x, y;
  struct nk_context *ctx = &nk_jake.ctx;
  JATGLwindow *win = nk_jake.win;

  JATGL_GetWindowSize(win, &nk_jake.width, &nk_jake.height);
  JATGL_GetFrameBufferSize(win, &nk_jake.display_width, &nk_jake.display_height);
  nk_jake.fb_scale.x = (float)nk_jake.display_width / (float)nk_jake.width;
  nk_jake.fb_scale.y = (float)nk_jake.display_height / (float)nk_jake.height;

  nk_input_begin(ctx);
  for(i = 0; i < nk_jake.text_len; ++i)
    nk_input_unicode(ctx, nk_jake.text[i]);

#ifdef NK_JAKE_GL_MOUSE_GRABBING
  /* optional grabbing behavior */
  if(ctx->input.mouse.grab)
    jakeSetInputMode(nk_jake.win, JAKE_CURSOR, JAKE_CURSOR_HIDDEN);
  else if(ctx->input.mouse.ungrab)
    jakeSetInputMode(nk_jake.win, JAKE_CURSOR, JAKE_CURSOR_NORMAL);
#endif

  nk_input_key(ctx, NK_KEY_DEL, JATGL_GetKeyState(win, JATGL_KEY_DELETE) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_ENTER, JATGL_GetKeyState(win, JATGL_KEY_ENTER) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_TAB, JATGL_GetKeyState(win, JATGL_KEY_TAB) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_BACKSPACE, JATGL_GetKeyState(win, JATGL_KEY_BACKSPACE) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_UP, JATGL_GetKeyState(win, JATGL_KEY_UP) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_DOWN, JATGL_GetKeyState(win, JATGL_KEY_DOWN) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_TEXT_START, JATGL_GetKeyState(win, JATGL_KEY_HOME) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_TEXT_END, JATGL_GetKeyState(win, JATGL_KEY_END) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_SCROLL_START, JATGL_GetKeyState(win, JATGL_KEY_HOME) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_SCROLL_END, JATGL_GetKeyState(win, JATGL_KEY_END) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_SCROLL_DOWN, JATGL_GetKeyState(win, JATGL_KEY_PAGE_DOWN) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_SCROLL_UP, JATGL_GetKeyState(win, JATGL_KEY_PAGE_UP) == JATGL_PRESS);
  nk_input_key(ctx, NK_KEY_SHIFT, JATGL_GetKeyState(win, JATGL_KEY_LEFT_SHIFT) == JATGL_PRESS ||
                                      JATGL_GetKeyState(win, JATGL_KEY_RIGHT_SHIFT) == JATGL_PRESS);

  if(JATGL_GetKeyState(win, JATGL_KEY_LEFT_CONTROL) == JATGL_PRESS ||
     JATGL_GetKeyState(win, JATGL_KEY_RIGHT_CONTROL) == JATGL_PRESS)
  {
    nk_input_key(ctx, NK_KEY_COPY, JATGL_GetKeyState(win, JATGL_KEY_C) == JATGL_PRESS);

    nk_input_key(ctx, NK_KEY_PASTE, JATGL_GetKeyState(win, JATGL_KEY_V) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_CUT, JATGL_GetKeyState(win, JATGL_KEY_X) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_TEXT_UNDO, JATGL_GetKeyState(win, JATGL_KEY_Z) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_TEXT_REDO, JATGL_GetKeyState(win, JATGL_KEY_R) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_TEXT_WORD_LEFT, JATGL_GetKeyState(win, JATGL_KEY_LEFT) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_TEXT_WORD_RIGHT, JATGL_GetKeyState(win, JATGL_KEY_RIGHT) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_TEXT_LINE_START, JATGL_GetKeyState(win, JATGL_KEY_B) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_TEXT_LINE_END, JATGL_GetKeyState(win, JATGL_KEY_E) == JATGL_PRESS);
  }
  else
  {
    nk_input_key(ctx, NK_KEY_LEFT, JATGL_GetKeyState(win, JATGL_KEY_LEFT) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_RIGHT, JATGL_GetKeyState(win, JATGL_KEY_RIGHT) == JATGL_PRESS);
    nk_input_key(ctx, NK_KEY_COPY, 0);
    nk_input_key(ctx, NK_KEY_PASTE, 0);
    nk_input_key(ctx, NK_KEY_CUT, 0);
    nk_input_key(ctx, NK_KEY_SHIFT, 0);
  }

  JATGL_GetMousePosition(win, &x, &y);
  nk_input_motion(ctx, (int)x, (int)y);
#ifdef NK_JAKE_GL_MOUSE_GRABBING
  if(ctx->input.mouse.grabbed)
  {
    jakeSetCursorPos(nk_jake.win, ctx->input.mouse.prev.x, ctx->input.mouse.prev.y);
    ctx->input.mouse.pos.x = ctx->input.mouse.prev.x;
    ctx->input.mouse.pos.y = ctx->input.mouse.prev.y;
  }
#endif
  nk_input_button(ctx, NK_BUTTON_LEFT, (int)x, (int)y,
                  JATGL_GetMouseButtonState(win, JATGL_MOUSE_BUTTON_LEFT) == JATGL_PRESS);
  nk_input_button(ctx, NK_BUTTON_MIDDLE, (int)x, (int)y,
                  JATGL_GetMouseButtonState(win, JATGL_MOUSE_BUTTON_MIDDLE) == JATGL_PRESS);
  nk_input_button(ctx, NK_BUTTON_RIGHT, (int)x, (int)y,
                  JATGL_GetMouseButtonState(win, JATGL_MOUSE_BUTTON_RIGHT) == JATGL_PRESS);
  nk_input_button(ctx, NK_BUTTON_DOUBLE, (int)nk_jake.double_click_pos.x,
                  (int)nk_jake.double_click_pos.y, nk_jake.is_double_click_down);
  nk_input_scroll(ctx, nk_jake.scroll);
  nk_input_end(&nk_jake.ctx);
  nk_jake.text_len = 0;
  nk_jake.scroll = nk_vec2(0, 0);
}

NK_API
void nk_jake_shutdown(void)
{
  nk_font_atlas_clear(&nk_jake.atlas);
  nk_free(&nk_jake.ctx);
  nk_jake_device_destroy();
  memset(&nk_jake, 0, sizeof(nk_jake));
}

#endif
