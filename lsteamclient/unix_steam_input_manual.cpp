#include "unix_private.h"

#if 0
#pragma makedep unix
#endif

#include <unordered_map>

#ifdef __linux__
#include <X11/keysym.h>
#endif

#ifdef __linux__
static const uint32_t vk_to_xkeysym[0xFF] =
{
    0,
    0,
    0,
    XK_Cancel,
    0,
    0,
    0,
    0,
    XK_BackSpace,
    XK_Tab,
    0,
    0,
    XK_Clear,
    XK_Return,
    0,
    0,
    XK_Shift_L,
    XK_Control_L,
    XK_Alt_L,
    XK_Pause,
    XK_Caps_Lock,
    0,
    0,
    0,
    0,
    0,
    0,
    XK_Escape,
    XK_Henkan_Mode,
    XK_Muhenkan,
    0,
    0,
    ' ',
    XK_Prior,
    XK_Next,
    XK_End,
    XK_Home,
    XK_Left,
    XK_Up,
    XK_Right,
    XK_Down,
    XK_Select,
    XK_Print,
    XK_Execute,
    XK_Print,
    XK_Insert,
    XK_Delete,
    XK_Help,

    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',

    XK_Super_L,
    XK_Super_R,
    XK_Menu,
    0,
    0,
    XK_KP_0,
    XK_KP_1,
    XK_KP_2,
    XK_KP_3,
    XK_KP_4,
    XK_KP_5,
    XK_KP_6,
    XK_KP_7,
    XK_KP_8,
    XK_KP_9,
    XK_KP_Multiply,
    XK_KP_Add,
    XK_KP_Separator,
    XK_KP_Subtract,
    XK_KP_Decimal,
    XK_KP_Divide,
    XK_F1,
    XK_F2,
    XK_F3,
    XK_F4,
    XK_F5,
    XK_F6,
    XK_F7,
    XK_F8,
    XK_F9,
    XK_F10,
    XK_F11,
    XK_F12,
    XK_F13,
    XK_F14,
    XK_F15,
    XK_F16,
    XK_F17,
    XK_F18,
    XK_F19,
    XK_F20,
    XK_F21,
    XK_F22,
    XK_F23,
    XK_F24,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    XK_Num_Lock,
    XK_Scroll_Lock,
    XK_KP_Equal,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    XK_Shift_L,
    XK_Shift_R,
    XK_Control_L,
    XK_Control_R,
    XK_Alt_L,
    XK_Alt_R,

};

uint32_t manual_convert_nNativeKeyCode( uint32_t win_vk )
{
    if(win_vk < sizeof(vk_to_xkeysym) / sizeof(*vk_to_xkeysym))
        return vk_to_xkeysym[win_vk];
    return 0;
}
#elif defined(__APPLE__)
uint32_t manual_convert_nNativeKeyCode( uint32_t win_vk )
{
    return 0;
}
#else
#error You must implement VK<->Native keysym conversion for this platform.
#endif

typedef std::unordered_map< uint64_t, char * > glyph_cache;
static glyph_cache input_cache, input_cache_svg, input_cache_png, xbox_cache, controller_cache;

static const char *glyph_cache_lookup( glyph_cache &cache, const char *str, uint16_t origin,
                                       uint32_t flags, uint16_t size )
{
    uint64_t key = (uint64_t)flags << 32 | (uint64_t)size << 16 | origin;

    if (cache.find( key ) == cache.end())
    {
        char *dos_path = (char *)malloc( PATH_MAX );
        steamclient_unix_path_to_dos_path( 1, str, dos_path, PATH_MAX, 0 );
        cache[key] = dos_path;
    }

    return cache[key];
}

template< typename Iface, typename Params >
static NTSTATUS ISteamController_GetGlyphForActionOrigin( Iface *iface, Params *params, bool wow64 )
{
    if (!(params->_ret = iface->GetGlyphForActionOrigin( params->eOrigin ))) return 0;
    params->_ret = glyph_cache_lookup( controller_cache, params->_ret, params->eOrigin, 0, 0 );
    return 0;
}

template< typename Iface, typename Params >
static NTSTATUS ISteamController_GetGlyphForXboxOrigin( Iface *iface, Params *params, bool wow64 )
{
    if (!(params->_ret = iface->GetGlyphForXboxOrigin( params->eOrigin ))) return 0;
    params->_ret = glyph_cache_lookup( xbox_cache, params->_ret, params->eOrigin, 0, 0 );
    return 0;
}

template< typename Iface, typename Params >
static NTSTATUS ISteamInput_GetGlyphForActionOrigin( Iface *iface, Params *params, bool wow64 )
{
    if (!(params->_ret = iface->GetGlyphForActionOrigin( params->eOrigin ))) return 0;
    params->_ret = glyph_cache_lookup( input_cache, params->_ret, params->eOrigin, 0, 0 );
    return 0;
}

template< typename Iface, typename Params >
static NTSTATUS ISteamInput_GetGlyphForXboxOrigin( Iface *iface, Params *params, bool wow64 )
{
    if (!(params->_ret = iface->GetGlyphForXboxOrigin( params->eOrigin ))) return 0;
    params->_ret = glyph_cache_lookup( xbox_cache, params->_ret, params->eOrigin, 0, 0 );
    return 0;
}

static void (W_CDECL *w_EnableActionEventCallbacks_152)( SteamInputActionEvent_t * );
static void U_CDECL u_SteamInputActionEventCallbackPointer_152( SteamInputActionEvent_t *dat )
{
    if (w_EnableActionEventCallbacks_152) queue_cdecl_func_callback( (w_cdecl_func)w_EnableActionEventCallbacks_152, dat, sizeof(*dat) );
}

template< typename Iface, typename Params >
NTSTATUS ISteamInput_EnableActionEventCallbacks( Iface *iface, Params *params, bool wow64 )
{
    w_EnableActionEventCallbacks_152 = params->pCallback;
    iface->EnableActionEventCallbacks( params->pCallback ? &u_SteamInputActionEventCallbackPointer_152 : NULL );
    return 0;
}

template< typename Iface, typename Params >
static NTSTATUS ISteamInput_GetGlyphPNGForActionOrigin( Iface *iface, Params *params, bool wow64 )
{
    if (!(params->_ret = iface->GetGlyphPNGForActionOrigin( params->eOrigin, params->eSize, params->unFlags ))) return 0;
    params->_ret = glyph_cache_lookup( input_cache_png, params->_ret, params->eOrigin, params->unFlags, params->eSize );
    return 0;
}

template< typename Iface, typename Params >
static NTSTATUS ISteamInput_GetGlyphSVGForActionOrigin( Iface *iface, Params *params, bool wow64 )
{
    if (!(params->_ret = iface->GetGlyphSVGForActionOrigin( params->eOrigin, params->unFlags ))) return 0;
    params->_ret = glyph_cache_lookup( input_cache_svg, params->_ret, params->eOrigin, params->unFlags, 0 );
    return 0;
}

template< typename Iface, typename Params >
static NTSTATUS ISteamInput_GetGlyphForActionOrigin_Legacy( Iface *iface, Params *params, bool wow64 )
{
    if (!(params->_ret = iface->GetGlyphForActionOrigin_Legacy( params->eOrigin ))) return 0;
    params->_ret = glyph_cache_lookup( input_cache, params->_ret, params->eOrigin, 0, 0 );
    return 0;
}

LSTEAMCLIENT_UNIX_IMPL( ISteamController, SteamController005, GetGlyphForActionOrigin );

LSTEAMCLIENT_UNIX_IMPL( ISteamController, SteamController006, GetGlyphForActionOrigin );

LSTEAMCLIENT_UNIX_IMPL( ISteamController, SteamController007, GetGlyphForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamController, SteamController007, GetGlyphForXboxOrigin );

LSTEAMCLIENT_UNIX_IMPL( ISteamController, SteamController008, GetGlyphForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamController, SteamController008, GetGlyphForXboxOrigin );

LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput001, GetGlyphForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput001, GetGlyphForXboxOrigin );

LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput002, GetGlyphForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput002, GetGlyphForXboxOrigin );

LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput005, EnableActionEventCallbacks );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput005, GetGlyphPNGForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput005, GetGlyphSVGForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput005, GetGlyphForActionOrigin_Legacy );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput005, GetGlyphForXboxOrigin );

LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput006, EnableActionEventCallbacks );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput006, GetGlyphPNGForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput006, GetGlyphSVGForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput006, GetGlyphForActionOrigin_Legacy );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput006, GetGlyphForXboxOrigin );

LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput007, EnableActionEventCallbacks );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput007, GetGlyphPNGForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput007, GetGlyphSVGForActionOrigin );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput007, GetGlyphForActionOrigin_Legacy );
LSTEAMCLIENT_UNIX_IMPL( ISteamInput, SteamInput007, GetGlyphForXboxOrigin );
