//
//  MetalDraw.hpp
//  MetalTriangleCPP
//
//  Created by Jake on 10/12/2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#pragma once

#include "metal/official/metal-cpp.h"

struct MetalDraw
{
  void Loaded();

  void Draw(CA::MetalDrawable *pMetalDrawable);

  MTL::Device *device;
  MTL::RenderPipelineState *pipeline;
  MTL::CommandQueue *commandQueue;
  MTL::Buffer *positionBuffer;
  MTL::Buffer *positionBuffer2;
  MTL::Buffer *colorBuffer;
  MTL::Buffer *colorBuffer2;

  MTL::RenderPipelineState *debugPipeline;
  MTL::Buffer *debugUBOBuffer;

  MTL::Texture *fb1;

private:
  void BuildDevice();
  void BuildVertexBuffers();
  void BuildPipeline();
  void CopyFrameBuffer(MTL::Texture *framebuffer);
};

MetalDraw *CreateMetalDraw();
