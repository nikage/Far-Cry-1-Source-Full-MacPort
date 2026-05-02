////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MetalCREScreenProcess.mm
//  Description: Metal implementation of CREScreenProcess.
//               Provides constructor, parameter accessors, and reset logic.
//               mfDraw/mfPrepare are no-ops; the Metal renderer drives
//               screen fades directly.
// -------------------------------------------------------------------------

#if defined(__APPLE__) && defined(__MACH__)

#include "MetalRenderPCH.h"
#include "../Common/RendElements/CREScreenCommon.h"
#include "CREScreenProcess.h"

extern IConsole *iConsole;

#define SET_PARAMETER(pProcess, pParam, pType, pValue) \
    case (pProcess): (pParam) = *((pType*)(pValue)); break;

#define RETURN_PARAMETER(pProcess, pParam) \
    case (pProcess): return (void*)&(pParam);

void CScreenVars::Create(void)
{
    if (iConsole)
    {
        m_pCVDisableSfx           = iConsole->GetCVar("r_DisableSfx");
        m_pCVResetSfx             = iConsole->GetCVar("r_ResetScreenFx");
        m_pCVNormalGlare          = iConsole->GetCVar("r_Glare");
        m_pCVMotionBlur           = iConsole->GetCVar("r_MotionBlur");
        m_pCVScreenColorTransfer  = iConsole->GetCVar("r_ScreenColorTransfer");
        m_pCVMotionBlurAmount     = iConsole->GetCVar("r_MotionBlurAmount");
        m_pCVMotionBlurDisplace   = iConsole->GetCVar("r_MotionBlurDisplace");
        m_pCVRenderMode           = iConsole->GetCVar("r_RenderMode");

        m_pCVStencilShadows = iConsole->GetCVar("e_stencil_shadows");
        m_iPrevStencilShadows = m_pCVStencilShadows ? m_pCVStencilShadows->GetIVal() : 0;

        m_pCVShadowMaps = iConsole->GetCVar("e_shadow_maps");
        m_iPrevShadowMaps = m_pCVShadowMaps ? m_pCVShadowMaps->GetIVal() : 0;

        m_pCVVolFog = iConsole->GetCVar("r_VolumetricFog");
        m_iPrevVolFog = m_pCVVolFog ? m_pCVVolFog->GetIVal() : 0;

        m_pCVFog = iConsole->GetCVar("e_fog");
        m_iPrevFog = m_pCVFog ? m_pCVFog->GetIVal() : 0;

        m_pCVMaxTexLodBias = iConsole->GetCVar("r_MaxTexLodBias");
        m_fPrevMaxTexLodBias = m_pCVMaxTexLodBias ? m_pCVMaxTexLodBias->GetFVal() : 0.0f;

        m_pCVHeatVision = iConsole->GetCVar("r_Cryvision");
        m_iHeatVisionActive = m_pCVHeatVision ? m_pCVHeatVision->GetIVal() : 0;

        ICVar *pHudFadeAmount = iConsole->GetCVar("hud_fadeamount");
        if (pHudFadeAmount)
            pHudFadeAmount->Set(1);
    }

    m_bFadeActive       = 0;
    m_fFadeTime         = 0;
    m_fFadePreTime      = 0;
    m_fFadeCurrPreTime  = 0;
    m_fFadeCurrTime     = 0;
}

void CScreenVars::Release(void)
{
}

void CScreenVars::Reset(void)
{
    m_bColorTransferActive = 0;
    m_pColorTransferColor.set(0, 0, 0, 0);
    m_fColorTransferAmount = 1;

    m_bBlurActive  = 0;
    m_fBlurAmount  = 1.0f;
    m_pBlurColor.set(1, 1, 1, 1);

    m_iNightVisionActive = 0;
    m_pNightVisionColor.set(-0.1f, 0.2f, 0.11f, 1.0f);

    if (m_pCVHeatVision)
        m_iHeatVisionActive = m_pCVHeatVision->GetIVal();
    else
        m_iHeatVisionActive = 0;

    m_bFlashBangActive     = 0;
    m_fFlashBangTimeScale  = 1.0f;
    m_fFlashBangTimeOut    = 1.0f;
    m_fFlashBangFlashPosX  = 200;
    m_fFlashBangFlashPosY  = 100;
    m_fFlashBangFlashSizeX = 400;
    m_fFlashBangFlashSizeY = 400;

    m_bScreenTexActive = 0;
    m_pCurrGlareMapConst.set(0.2f, 0.2f, 0.2f, 1.0f);
    m_pCurrSaturation.set(0.0f, 0.0f, 0.0f, 0.2f);
    m_pCurrContrast.set(0.0f, 0.0f, 0.85f, 0.15f);

    if (iConsole)
    {
        ICVar *pHudFadeAmount = iConsole->GetCVar("hud_fadeamount");
        if (pHudFadeAmount)
            pHudFadeAmount->Set(1);
    }

    m_bFadeActive       = 0;
    m_fFadeTime         = 0;
    m_fFadePreTime      = 0;
    m_fFadeCurrPreTime  = 0;
    m_fFadeCurrTime     = 0;
    m_pFadeColor.set(0, 0, 0, 0);
    m_pFadeCurrColor.set(0, 0, 0, 0);
}

CREScreenProcess::CREScreenProcess()
{
    mfSetType(eDATA_ScreenProcess);
    mfUpdateFlags(FCEF_TRANSFORM);
    m_pVars = 0;

    if (!m_pVars)
    {
        m_pVars = new CScreenVars;
        m_pVars->Create();
    }
}

CREScreenProcess::~CREScreenProcess()
{
    SAFE_DELETE(m_pVars)
}

void CREScreenProcess::mfPrepare()
{
}

bool CREScreenProcess::mfDraw(SShader *, SShaderPass *)
{
    return false;
}

bool CREScreenProcess::mfDrawLowSpec(SShader *, SShaderPass *)
{
    return false;
}

void CREScreenProcess::mfActivate(int pProcess)
{
    if (!m_pVars)
        return;

    switch (pProcess)
    {
    case SCREENPROCESS_FADE:
        if (m_pVars->m_fFadeTime)
            m_pVars->m_bFadeActive = 1;
        else
        {
            m_pVars->m_bFadeActive      = 0;
            m_pVars->m_fFadePreTime     = 0.0f;
            m_pVars->m_fFadeCurrPreTime = 0.0f;
        }
        break;
    case SCREENPROCESS_BLUR:
        m_pVars->m_bBlurActive = 1;
        break;
    case SCREENPROCESS_COLORTRANSFER:
        m_pVars->m_bColorTransferActive = 1;
        break;
    case SCREENPROCESS_MOTIONBLUR:
        m_pVars->m_bMotionBlurActive = 1;
        break;
    case SCREENPROCESS_GLARE:
        m_pVars->m_bGlareActive = 1;
        break;
    case SCREENPROCESS_NIGHTVISION:
    case SCREENPROCESS_HEATVISION:
        if (m_pVars->m_pCVHeatVision)
            m_pVars->m_pCVHeatVision->Set(1);
        break;
    case SCREENPROCESS_CARTOON:
        m_pVars->m_bCartoonActive = 1;
        if (m_pVars->m_pCVMaxTexLodBias)
        {
            m_pVars->m_fPrevMaxTexLodBias = m_pVars->m_pCVMaxTexLodBias->GetFVal();
            m_pVars->m_pCVMaxTexLodBias->Set(-1.5f);
        }
        break;
    case SCREENPROCESS_FLASHBANG:
        m_pVars->m_bFlashBangActive  = 1;
        m_pVars->m_fFlashBangTimeOut = 1.0f;
        break;
    case SCREENPROCESS_DOF:
        m_pVars->m_bDofActive        = 1;
        m_pVars->m_fDofFocalDistance = 20.0f;
        break;
    default:
        break;
    }
}

void CREScreenProcess::mfReset()
{
    if (m_pVars)
        m_pVars->Reset();
}

int CREScreenProcess::mfSetParameter(int iProcess, int iParams, void *dwValue)
{
    switch (iProcess)
    {
    case SCREENPROCESS_FADE:
        switch (iParams)
        {
            SET_PARAMETER(SCREENPROCESS_FADECOLOR, m_pVars->m_pFadeColor, color4f, dwValue)

        case SCREENPROCESS_ACTIVE:
            if (*((bool*)dwValue) == 1)
                m_pVars->m_bFadeActive = 1;
            else
            {
                m_pVars->m_bFadeActive      = 0;
                m_pVars->m_fFadePreTime     = 0.0f;
                m_pVars->m_fFadeCurrPreTime = 0.0f;
            }
            break;

        case SCREENPROCESS_TRANSITIONTIME:
            m_pVars->m_fFadeTime     = *((float*)dwValue);
            m_pVars->m_fFadeCurrTime = (float)fabs(*((float*)dwValue));
            break;

            SET_PARAMETER(SCREENPROCESS_PRETRANSITIONTIME, m_pVars->m_fFadePreTime, float, dwValue)
        }
        break;

    case SCREENPROCESS_BLUR:
        switch (iParams)
        {
            SET_PARAMETER(SCREENPROCESS_BLURAMOUNT, m_pVars->m_fBlurAmount, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bBlurActive, bool, dwValue)
        case SCREENPROCESS_BLURCOLORRED:   m_pVars->m_pBlurColor.r = *(float*)dwValue; break;
        case SCREENPROCESS_BLURCOLORGREEN: m_pVars->m_pBlurColor.g = *(float*)dwValue; break;
        case SCREENPROCESS_BLURCOLORBLUE:  m_pVars->m_pBlurColor.b = *(float*)dwValue; break;
        }
        break;

    case SCREENPROCESS_COLORTRANSFER:
        switch (iParams)
        {
            SET_PARAMETER(SCREENPROCESS_COLORTRANSFERAMOUNT, m_pVars->m_fColorTransferAmount, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_COLORTRANSFERCOLOR, m_pVars->m_pColorTransferColor, color4f, dwValue)
            SET_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bColorTransferActive, bool, dwValue)
        }
        break;

    case SCREENPROCESS_MOTIONBLUR:
        switch (iParams)
        {
            SET_PARAMETER(SCREENPROCESS_MOTIONBLURDISPLACE, m_pVars->m_iMotionBlurDisplace, int, dwValue)
            SET_PARAMETER(SCREENPROCESS_MOTIONBLURAMOUNT, m_pVars->m_fMotionBlurAmount, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_MOTIONBLURTYPE, m_pVars->m_iMotionBlurType, int, dwValue)
            SET_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bMotionBlurActive, bool, dwValue)
        }
        break;

    case SCREENPROCESS_GLARE:
        switch (iParams)
        {
            SET_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bGlareActive, bool, dwValue)
            SET_PARAMETER(SCREENPROCESS_GLAREAMOUNT, m_pVars->m_fGlareAmount, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_GLARELUMSIZE, m_pVars->m_iGlareLumSize, int, dwValue)
            SET_PARAMETER(SCREENPROCESS_GLAREMAXAMOUNT, m_pVars->m_fGlareMaxAmount, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_GLAREBOXSIZE, m_pVars->m_iGlareSize, int, dwValue)
            SET_PARAMETER(SCREENPROCESS_GLARETHRESHOLD, m_pVars->m_fGlareThreshold, float, dwValue)
        }
        break;

    case SCREENPROCESS_NIGHTVISION:
        switch (iParams)
        {
        case SCREENPROCESS_ACTIVE:
            if (m_pVars->m_pCVHeatVision)
                m_pVars->m_pCVHeatVision->Set(*((int*)dwValue));
            break;
        case SCREENPROCESS_NIGHTVISIONCOLORRED:   m_pVars->m_pNightVisionColor.r = *(float*)dwValue; break;
        case SCREENPROCESS_NIGHTVISIONCOLORGREEN: m_pVars->m_pNightVisionColor.g = *(float*)dwValue; break;
        case SCREENPROCESS_NIGHTVISIONCOLORBLUE:  m_pVars->m_pNightVisionColor.b = *(float*)dwValue; break;
        }
        break;

    case SCREENPROCESS_HEATVISION:
        switch (iParams)
        {
        case SCREENPROCESS_ACTIVE:
            if (m_pVars->m_pCVHeatVision)
                m_pVars->m_pCVHeatVision->Set(*((int*)dwValue));
            break;
        }
        break;

    case SCREENPROCESS_FLASHBANG:
        switch (iParams)
        {
        case SCREENPROCESS_ACTIVE:
            m_pVars->m_bFlashBangActive  = *((bool*)dwValue);
            m_pVars->m_fFlashBangTimeOut = 1.0f;
            break;
            SET_PARAMETER(SCREENPROCESS_FLASHBANGTIMESCALE, m_pVars->m_fFlashBangTimeScale, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_FLASHBANGFLASHPOSX, m_pVars->m_fFlashBangFlashPosX, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_FLASHBANGFLASHPOSY, m_pVars->m_fFlashBangFlashPosY, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_FLASHBANGFLASHSIZEX, m_pVars->m_fFlashBangFlashSizeX, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_FLASHBANGFLASHSIZEY, m_pVars->m_fFlashBangFlashSizeY, float, dwValue)
            SET_PARAMETER(SCREENPROCESS_FLASHBANGFORCEAFTERIMAGE, m_pVars->m_iFlashBangForce, int, dwValue)
        }
        break;

    case SCREENPROCESS_CARTOON:
        switch (iParams)
        {
        case SCREENPROCESS_ACTIVE:
            m_pVars->m_bCartoonActive = *((bool*)dwValue);
            break;
        }
        break;

    case SCREENPROCESS_DOF:
        switch (iParams)
        {
            SET_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bDofActive, bool, dwValue)
            SET_PARAMETER(SCREENPROCESS_DOFFOCALDISTANCE, m_pVars->m_fDofFocalDistance, float, dwValue)
        }
        break;

    case SCREENPROCESS_SCREENTEX:
        switch (iParams)
        {
            SET_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bScreenTexActive, bool, dwValue)
        }
        break;

    default:
        break;
    }

    return 0;
}

void *CREScreenProcess::mfGetParameter(int iProcess, int iParams)
{
    switch (iProcess)
    {
    case SCREENPROCESS_FADE:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_TRANSITIONTIME, m_pVars->m_fFadeTime)
            RETURN_PARAMETER(SCREENPROCESS_PRETRANSITIONTIME, m_pVars->m_fFadePreTime)
            RETURN_PARAMETER(SCREENPROCESS_FADECOLOR, m_pVars->m_pFadeColor)
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bFadeActive)
        }
        break;

    case SCREENPROCESS_BLUR:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_BLURAMOUNT, m_pVars->m_fBlurAmount)
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bBlurActive)
            RETURN_PARAMETER(SCREENPROCESS_BLURCOLORRED, m_pVars->m_pBlurColor.r)
            RETURN_PARAMETER(SCREENPROCESS_BLURCOLORGREEN, m_pVars->m_pBlurColor.g)
            RETURN_PARAMETER(SCREENPROCESS_BLURCOLORBLUE, m_pVars->m_pBlurColor.b)
        }
        break;

    case SCREENPROCESS_COLORTRANSFER:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_COLORTRANSFERAMOUNT, m_pVars->m_fColorTransferAmount)
            RETURN_PARAMETER(SCREENPROCESS_COLORTRANSFERCOLOR, m_pVars->m_pColorTransferColor)
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bColorTransferActive)
        }
        break;

    case SCREENPROCESS_MOTIONBLUR:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_MOTIONBLURDISPLACE, m_pVars->m_iMotionBlurDisplace)
            RETURN_PARAMETER(SCREENPROCESS_MOTIONBLURAMOUNT, m_pVars->m_fMotionBlurAmount)
            RETURN_PARAMETER(SCREENPROCESS_MOTIONBLURTYPE, m_pVars->m_iMotionBlurType)
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bMotionBlurActive)
        }
        break;

    case SCREENPROCESS_GLARE:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bGlareActive)
            RETURN_PARAMETER(SCREENPROCESS_GLAREAMOUNT, m_pVars->m_fGlareAmount)
            RETURN_PARAMETER(SCREENPROCESS_GLARELUMSIZE, m_pVars->m_iGlareLumSize)
            RETURN_PARAMETER(SCREENPROCESS_GLAREMAXAMOUNT, m_pVars->m_fGlareMaxAmount)
            RETURN_PARAMETER(SCREENPROCESS_GLAREBOXSIZE, m_pVars->m_iGlareSize)
            RETURN_PARAMETER(SCREENPROCESS_GLARETHRESHOLD, m_pVars->m_fGlareThreshold)
        }
        break;

    case SCREENPROCESS_NIGHTVISION:
        switch (iParams)
        {
        case SCREENPROCESS_ACTIVE:
            if (m_pVars->m_pCVHeatVision)
                m_pVars->m_iNightVisionActive = m_pVars->m_pCVHeatVision->GetIVal();
            return (void*)&m_pVars->m_iNightVisionActive;
            RETURN_PARAMETER(SCREENPROCESS_NIGHTVISIONCOLORRED, m_pVars->m_pNightVisionColor.r)
            RETURN_PARAMETER(SCREENPROCESS_NIGHTVISIONCOLORGREEN, m_pVars->m_pNightVisionColor.g)
            RETURN_PARAMETER(SCREENPROCESS_NIGHTVISIONCOLORBLUE, m_pVars->m_pNightVisionColor.b)
        }
        break;

    case SCREENPROCESS_HEATVISION:
        switch (iParams)
        {
        case SCREENPROCESS_ACTIVE:
            if (m_pVars->m_pCVHeatVision)
                m_pVars->m_iHeatVisionActive = m_pVars->m_pCVHeatVision->GetIVal();
            return (void*)&m_pVars->m_iHeatVisionActive;
        }
        break;

    case SCREENPROCESS_FLASHBANG:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bFlashBangActive)
            RETURN_PARAMETER(SCREENPROCESS_FLASHBANGTIMESCALE, m_pVars->m_fFlashBangTimeScale)
            RETURN_PARAMETER(SCREENPROCESS_FLASHBANGTIMEOUT, m_pVars->m_fFlashBangTimeOut)
            RETURN_PARAMETER(SCREENPROCESS_FLASHBANGFLASHPOSX, m_pVars->m_fFlashBangFlashPosX)
            RETURN_PARAMETER(SCREENPROCESS_FLASHBANGFLASHPOSY, m_pVars->m_fFlashBangFlashPosY)
            RETURN_PARAMETER(SCREENPROCESS_FLASHBANGFLASHSIZEX, m_pVars->m_fFlashBangFlashSizeX)
            RETURN_PARAMETER(SCREENPROCESS_FLASHBANGFLASHSIZEY, m_pVars->m_fFlashBangFlashSizeY)
            RETURN_PARAMETER(SCREENPROCESS_FLASHBANGFORCEAFTERIMAGE, m_pVars->m_iFlashBangForce)
        }
        break;

    case SCREENPROCESS_CARTOON:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bCartoonActive)
        }
        break;

    case SCREENPROCESS_DOF:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bDofActive)
            RETURN_PARAMETER(SCREENPROCESS_DOFFOCALDISTANCE, m_pVars->m_fDofFocalDistance)
        }
        break;

    case SCREENPROCESS_SCREENTEX:
        switch (iParams)
        {
            RETURN_PARAMETER(SCREENPROCESS_ACTIVE, m_pVars->m_bScreenTexActive)
        }
        break;

    default:
        break;
    }

    return 0;
}

#endif // __APPLE__
