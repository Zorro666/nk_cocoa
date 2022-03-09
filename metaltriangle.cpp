#include <stdlib.h>

#include "MetalDraw.h"
#include "apple_cocoa.h"

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
    exit(1);

  COCOAwindow *window = COCOA_NewWindow(640, 480, "Metal Triangle");
  if(!window)
  {
    COCOA_Shutdown();
    exit(1);
  }
  COCOA_SetKeyCallback(window, KeyCallback);

  MetalDraw *metalDraw = CreateMetalDraw();
  metalDraw->Loaded();

  MTL::Device *metalDevice = metalDraw->device;
  CA::MetalLayer *metalLayer = (CA::MetalLayer *)COCOA_SwitchLayerToMetal(window, metalDevice);

  while(!COCOA_WindowShouldClose(window) && !closeWindow)
  {
    CA::MetalDrawable *pMetalCppDrawable = (CA::MetalDrawable *)COCOA_NextDrawable(window);
    metalDraw->Draw(pMetalCppDrawable);

    COCOA_Poll();
  }

  COCOA_DeleteWindow(window);

  COCOA_Shutdown();
  exit(EXIT_SUCCESS);
}