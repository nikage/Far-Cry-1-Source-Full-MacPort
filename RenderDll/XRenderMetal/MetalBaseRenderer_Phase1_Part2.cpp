// Part 2: Buffer Management, State Management, and Drawing

#if defined(__APPLE__) && defined(__MACH__)

CVertexBuffer* CMetalBaseRenderer::CreateBuffer(int vertexcount, int vertexformat, 
                                                const char* szSource, bool bDynamic)
{
    if (vertexcount <= 0)
        return nullptr;
    
    CVertexBuffer* vb = new CVertexBuffer();
    if (!vb)
        return nullptr;
    
    vb->m_NumVerts = vertexcount;
    vb->m_vertexformat = vertexformat;
    vb->m_bDynamic = bDynamic ? 1 : 0;
    
    int vertexSize = GetVertexFormatSize(vertexformat);
    size_t bufferSize = vertexcount * vertexSize;
    
    MTLResourceOptions options = bDynamic ? MTLResourceStorageModeShared : MTLResourceStorageModeManaged;
    id<MTLBuffer> metalBuffer = [m_device newBufferWithLength:bufferSize options:options];
    
    if (!metalBuffer)
    {
        delete vb;
        return nullptr;
    }
    
    int bufferId = m_nextVertexBufferId++;
    if (bufferId >= (int)m_vertexBuffers.size())
    {
        m_vertexBuffers.resize(bufferId + 1, nil);
    }
    m_vertexBuffers[bufferId] = metalBuffer;
    
    vb->m_VS[VSF_GENERAL].m_VertBuf.m_nID = bufferId;
    vb->m_VS[VSF_GENERAL].m_VData = [metalBuffer contents];
    vb->m_VS[VSF_GENERAL].m_nItems = vertexcount;
    vb->m_VS[VSF_GENERAL].m_bDynamic = bDynamic;
    
    return vb;
}

void CMetalBaseRenderer::ReleaseBuffer(CVertexBuffer* bufptr)
{
    if (!bufptr)
        return;
    
    int bufferId = bufptr->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    if (bufferId > 0 && bufferId < (int)m_vertexBuffers.size())
    {
        m_vertexBuffers[bufferId] = nil;
    }
    
    delete bufptr;
}

void CMetalBaseRenderer::UpdateBuffer(CVertexBuffer* dest, const void* src, 
                                     int vertexcount, bool bUnLock, int nOffs, int Type)
{
    if (!dest || !src || vertexcount <= 0)
        return;
    
    int bufferId = dest->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    if (bufferId <= 0 || bufferId >= (int)m_vertexBuffers.size())
        return;
    
    id<MTLBuffer> metalBuffer = m_vertexBuffers[bufferId];
    if (!metalBuffer)
        return;
    
    int vertexSize = GetVertexFormatSize(dest->m_vertexformat);
    size_t copySize = vertexcount * vertexSize;
    size_t offset = nOffs * vertexSize;
    
    void* bufferData = (char*)[metalBuffer contents] + offset;
    memcpy(bufferData, src, copySize);
    
    if (metalBuffer.storageMode == MTLStorageModeManaged)
    {
        [metalBuffer didModifyRange:NSMakeRange(offset, copySize)];
    }
}

void CMetalBaseRenderer::CreateIndexBuffer(SVertexStream* dest, const void* src, int indexcount)
{
    if (!dest || !src || indexcount <= 0)
        return;
    
    size_t bufferSize = indexcount * sizeof(unsigned short);
    id<MTLBuffer> metalBuffer = [m_device newBufferWithBytes:src 
                                                      length:bufferSize 
                                                     options:MTLResourceStorageModeManaged];
    
    if (!metalBuffer)
        return;
    
    int bufferId = m_nextIndexBufferId++;
    if (bufferId >= (int)m_indexBuffers.size())
    {
        m_indexBuffers.resize(bufferId + 1, nil);
    }
    m_indexBuffers[bufferId] = metalBuffer;
    
    dest->m_VertBuf.m_nID = bufferId;
    dest->m_VData = [metalBuffer contents];
    dest->m_nItems = indexcount;
    dest->m_bDynamic = false;
}

void CMetalBaseRenderer::UpdateIndexBuffer(SVertexStream* dest, const void* src, 
                                          int indexcount, bool bUnLock)
{
    if (!dest || !src || indexcount <= 0)
        return;
    
    int bufferId = dest->m_VertBuf.m_nID;
    if (bufferId <= 0 || bufferId >= (int)m_indexBuffers.size())
        return;
    
    id<MTLBuffer> metalBuffer = m_indexBuffers[bufferId];
    if (!metalBuffer)
        return;
    
    size_t copySize = indexcount * sizeof(unsigned short);
    memcpy([metalBuffer contents], src, copySize);
    
    if (metalBuffer.storageMode == MTLStorageModeManaged)
    {
        [metalBuffer didModifyRange:NSMakeRange(0, copySize)];
    }
}

void CMetalBaseRenderer::ReleaseIndexBuffer(SVertexStream* dest)
{
    if (!dest)
        return;
    
    int bufferId = dest->m_VertBuf.m_nID;
    if (bufferId > 0 && bufferId < (int)m_indexBuffers.size())
    {
        m_indexBuffers[bufferId] = nil;
    }
    
    dest->Reset();
}

void* CMetalBaseRenderer::GetDynVBPtr(int nVerts, int& nOffs, int Pool)
{
    if (nVerts <= 0 || Pool < 0 || Pool >= NUM_DYNAMIC_VB_POOLS)
        return nullptr;
    
    DynamicVBPool& pool = m_dynamicVBPools[Pool];
    
    int vertexSize = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    size_t requiredSize = nVerts * vertexSize;
    
    if (pool.offset + requiredSize > pool.size)
    {
        pool.offset = 0;
    }
    
    nOffs = static_cast<int>(pool.offset / vertexSize);
    void* ptr = (char*)pool.cpuData + pool.offset;
    pool.offset += requiredSize;
    
    return ptr;
}

void CMetalBaseRenderer::DrawDynVB(int nOffs, int Pool, int nVerts)
{
    if (!m_renderEncoder || nVerts <= 0 || Pool < 0 || Pool >= NUM_DYNAMIC_VB_POOLS)
        return;
    
    DynamicVBPool& pool = m_dynamicVBPools[Pool];
    int vertexSize = sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    size_t offset = nOffs * vertexSize;
    
    [m_renderEncoder setVertexBuffer:pool.buffer offset:offset atIndex:0];
    [m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:nVerts];
    
    m_numDrawCalls++;
    m_numTriangles += nVerts / 3;
}

void CMetalBaseRenderer::DrawDynVB(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F* pBuf, 
                                  ushort* pInds, int nVerts, int nInds, int nPrimType)
{
    if (!m_renderEncoder || !pBuf || nVerts <= 0)
        return;
    
    int nOffs;
    void* dynPtr = GetDynVBPtr(nVerts, nOffs, 0);
    if (!dynPtr)
        return;
    
    memcpy(dynPtr, pBuf, nVerts * sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F));
    
    MTLPrimitiveType primType = ConvertPrimitiveType(nPrimType);
    
    if (pInds && nInds > 0)
    {
        size_t indexBufferSize = nInds * sizeof(ushort);
        id<MTLBuffer> indexBuffer = [m_device newBufferWithBytes:pInds 
                                                          length:indexBufferSize 
                                                         options:MTLResourceStorageModeShared];
        
        [m_renderEncoder setVertexBuffer:m_dynamicVBPools[0].buffer offset:nOffs atIndex:0];
        [m_renderEncoder drawIndexedPrimitives:primType 
                                    indexCount:nInds 
                                     indexType:MTLIndexTypeUInt16 
                                   indexBuffer:indexBuffer 
                             indexBufferOffset:0];
    }
    else
    {
        DrawDynVB(nOffs, 0, nVerts);
    }
    
    m_numDrawCalls++;
}

void CMetalBaseRenderer::DrawBuffer(CVertexBuffer* src, SVertexStream* indices, 
                                   int numindices, int offsindex, int prmode, 
                                   int vert_start, int vert_stop, CMatInfo* mi)
{
    if (!m_renderEncoder || !src)
        return;
    
    int bufferId = src->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    if (bufferId <= 0 || bufferId >= (int)m_vertexBuffers.size())
        return;
    
    id<MTLBuffer> vertexBuffer = m_vertexBuffers[bufferId];
    if (!vertexBuffer)
        return;
    
    [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    
    MTLPrimitiveType primType = ConvertPrimitiveType(prmode);
    
    if (indices && numindices > 0)
    {
        int indexBufferId = indices->m_VertBuf.m_nID;
        if (indexBufferId > 0 && indexBufferId < (int)m_indexBuffers.size())
        {
            id<MTLBuffer> indexBuffer = m_indexBuffers[indexBufferId];
            if (indexBuffer)
            {
                size_t indexOffset = offsindex * sizeof(unsigned short);
                [m_renderEncoder drawIndexedPrimitives:primType 
                                            indexCount:numindices 
                                             indexType:MTLIndexTypeUInt16 
                                           indexBuffer:indexBuffer 
                                     indexBufferOffset:indexOffset];
                
                m_numDrawCalls++;
                m_numTriangles += numindices / 3;
            }
        }
    }
    else
    {
        int vertCount = (vert_stop > 0) ? (vert_stop - vert_start) : src->m_NumVerts;
        [m_renderEncoder drawPrimitives:primType vertexStart:vert_start vertexCount:vertCount];
        
        m_numDrawCalls++;
        m_numTriangles += vertCount / 3;
    }
}

void CMetalBaseRenderer::DrawTriStrip(CVertexBuffer* src, int vert_num)
{
    if (!m_renderEncoder || !src)
        return;
    
    int bufferId = src->m_VS[VSF_GENERAL].m_VertBuf.m_nID;
    if (bufferId <= 0 || bufferId >= (int)m_vertexBuffers.size())
        return;
    
    id<MTLBuffer> vertexBuffer = m_vertexBuffers[bufferId];
    if (!vertexBuffer)
        return;
    
    [m_renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [m_renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip 
                        vertexStart:0 
                        vertexCount:vert_num];
    
    m_numDrawCalls++;
    m_numTriangles += vert_num - 2;
}

void CMetalBaseRenderer::SetFenceCompleted(CVertexBuffer* buffer)
{
    if (buffer)
    {
        buffer->m_bFenceSet = 0;
    }
}

void CMetalBaseRenderer::SetState(int State)
{
    m_currentState = State;
    
    if (State & GS_DEPTHWRITE)
        SetDepthWrite(true);
    else
        SetDepthWrite(false);
    
    if (State & GS_NODEPTHTEST)
        SetDepthTest(false);
    else
        SetDepthTest(true);
    
    if (State & GS_BLSRC_SRCALPHA)
    {
        SetBlending(true);
        SetBlendFactors(MTLBlendFactorSourceAlpha, MTLBlendFactorOneMinusSourceAlpha, 
                       MTLBlendOperationAdd);
    }
    else if (State & GS_BLSRC_ONE)
    {
        SetBlending(true);
        SetBlendFactors(MTLBlendFactorOne, MTLBlendFactorOne, MTLBlendOperationAdd);
    }
    else
    {
        SetBlending(false);
    }
    
    ApplyRenderState();
}

void CMetalBaseRenderer::SetCullMode(int mode)
{
    m_currentCullMode = mode;
    
    if (!m_renderEncoder)
        return;
    
    switch (mode)
    {
        case R_CULL_DISABLE:
        case R_CULL_NONE:
            [m_renderEncoder setCullMode:MTLCullModeNone];
            break;
        case R_CULL_FRONT:
            [m_renderEncoder setCullMode:MTLCullModeFront];
            break;
        case R_CULL_BACK:
        default:
            [m_renderEncoder setCullMode:MTLCullModeBack];
            break;
    }
}

void CMetalBaseRenderer::SetDepthTest(bool enabled)
{
    m_depthTestEnabled = enabled;
}

void CMetalBaseRenderer::SetDepthWrite(bool enabled)
{
    m_depthWriteEnabled = enabled;
}

void CMetalBaseRenderer::SetDepthFunction(MTLCompareFunction function)
{
    m_depthFunction = function;
}

void CMetalBaseRenderer::SetBlending(bool enabled)
{
    m_blendingEnabled = enabled;
}

void CMetalBaseRenderer::SetBlendFactors(MTLBlendFactor source, MTLBlendFactor dest, 
                                        MTLBlendOperation operation)
{
    m_sourceBlendFactor = source;
    m_destBlendFactor = dest;
    m_blendOperation = operation;
}

void CMetalBaseRenderer::ApplyRenderState()
{
    if (!m_renderEncoder || !m_stateCache)
        return;
    
    MetalDepthStencilStateKey dsKey;
    dsKey.depthTestEnabled = m_depthTestEnabled;
    dsKey.depthWriteEnabled = m_depthWriteEnabled;
    dsKey.depthCompareFunction = m_depthFunction;
    dsKey.stencilReadMask = 0xFF;
    dsKey.stencilWriteMask = 0xFF;
    
    id<MTLDepthStencilState> depthState = m_stateCache->GetOrCreateDepthStencilState(dsKey);
    if (depthState)
    {
        [m_renderEncoder setDepthStencilState:depthState];
        m_currentDepthStencilState = depthState;
    }
}

bool CMetalBaseRenderer::EnableFog(bool enable)
{
    m_fogEnabled = enable;
    return true;
}

void CMetalBaseRenderer::SetFog(float density, float fogstart, float fogend, 
                               const float* color, int fogmode)
{
}

void CMetalBaseRenderer::EnableTexGen(bool enable)
{
    m_texGenEnabled = enable;
}

void CMetalBaseRenderer::SetTexgen(float scaleX, float scaleY, float translateX, float translateY)
{
}

void CMetalBaseRenderer::SetTexgen3D(float x1, float y1, float z1, float x2, float y2, float z2)
{
}

void CMetalBaseRenderer::SetLodBias(float value)
{
    m_lodBias = value;
}

void CMetalBaseRenderer::EnableVSync(bool enable)
{
    m_vSyncEnabled = enable;
}

void CMetalBaseRenderer::EnableTMU(bool enable)
{
}

void CMetalBaseRenderer::SelectTMU(int tnum)
{
    m_currentTMU = tnum;
}

MTLPrimitiveType CMetalBaseRenderer::ConvertPrimitiveType(int prmode)
{
    switch (prmode)
    {
        case R_PRIMV_TRIANGLES:
            return MTLPrimitiveTypeTriangle;
        case R_PRIMV_TRIANGLE_STRIP:
            return MTLPrimitiveTypeTriangleStrip;
        case R_PRIMV_TRIANGLE_FAN:
            return MTLPrimitiveTypeTriangle;
        default:
            return MTLPrimitiveTypeTriangle;
    }
}

MTLCompareFunction CMetalBaseRenderer::ConvertCompareFunction(int func)
{
    switch (func)
    {
        case 0: return MTLCompareFunctionNever;
        case 1: return MTLCompareFunctionLess;
        case 2: return MTLCompareFunctionEqual;
        case 3: return MTLCompareFunctionLessEqual;
        case 4: return MTLCompareFunctionGreater;
        case 5: return MTLCompareFunctionNotEqual;
        case 6: return MTLCompareFunctionGreaterEqual;
        case 7: return MTLCompareFunctionAlways;
        default: return MTLCompareFunctionLess;
    }
}

MTLBlendFactor CMetalBaseRenderer::ConvertBlendFactor(int factor)
{
    switch (factor)
    {
        case 0: return MTLBlendFactorZero;
        case 1: return MTLBlendFactorOne;
        case 2: return MTLBlendFactorSourceColor;
        case 3: return MTLBlendFactorOneMinusSourceColor;
        case 4: return MTLBlendFactorSourceAlpha;
        case 5: return MTLBlendFactorOneMinusSourceAlpha;
        case 6: return MTLBlendFactorDestinationAlpha;
        case 7: return MTLBlendFactorOneMinusDestinationAlpha;
        default: return MTLBlendFactorOne;
    }
}

int CMetalBaseRenderer::GetVertexFormatSize(int vertexformat)
{
    switch (vertexformat)
    {
        case VERTEX_FORMAT_P3F:
            return sizeof(struct_VERTEX_FORMAT_P3F);
        case VERTEX_FORMAT_P3F_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
        case VERTEX_FORMAT_P3F_N:
            return sizeof(struct_VERTEX_FORMAT_P3F_N);
        case VERTEX_FORMAT_P3F_N_COL4UB_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_COL4UB_TEX2F);
        case VERTEX_FORMAT_P3F_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_TEX2F);
        case VERTEX_FORMAT_P3F_N_TEX2F:
            return sizeof(struct_VERTEX_FORMAT_P3F_N_TEX2F);
        case VERTEX_FORMAT_P3F_COL4UB:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB);
        default:
            return sizeof(struct_VERTEX_FORMAT_P3F_COL4UB_TEX2F);
    }
}

int CMetalBaseRenderer::GetWidth()
{
    return m_width;
}

int CMetalBaseRenderer::GetHeight()
{
    return m_height;
}

int CMetalBaseRenderer::GetColorBpp()
{
    return m_cbpp;
}

int CMetalBaseRenderer::GetDepthBpp()
{
    return m_zbpp;
}

int CMetalBaseRenderer::GetStencilBpp()
{
    return m_sbpp;
}

void CMetalBaseRenderer::CheckError(const char* comment)
{
}

int CMetalBaseRenderer::GetFeatures()
{
    if (!m_device)
        return 0;
        
    int features = 0;
    features |= RFT_MULTITEXTURE;
    features |= RFT_BUMP;
    features |= RFT_HWGAMMA;
    features |= RFT_ALLOWRECTTEX;
    features |= RFT_COMPRESSTEXTURE;
    features |= RFT_ALLOWANISOTROPIC;
    features |= RFT_SUPPORTZBIAS;
    features |= RFT_HW_VS;
    features |= RFT_HW_PS20;
    features |= RFT_HW_PS30;
    features |= RFT_HW_HDR;
    features |= RFT_SUPPORTFSAA;
    features |= RFT_DEPTHMAPS;
    
    return features;
}

int CMetalBaseRenderer::GetMaxTextureMemory()
{
    if (!m_device)
        return 0;
    
    return 256 * 1024 * 1024;
}

#endif

