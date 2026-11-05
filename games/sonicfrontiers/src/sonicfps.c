#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *name;
    const unsigned char *pat;
    const char *mask;
    size_t len;
    unsigned char *addr;
    int done;
} Sig;

static Sig g_sigs[] = {
    {"sleep_call",
     (const unsigned char *)"\xE8\x00\x00\x00\x00\x48\x8D\x4C\x24\x00\xE8\x00\x00\x00\x00\x48\x8B\x4C\x24\x00\x48\x8B\x43\x20",
     "x????xxxx?x????xxxx?xxxx", 24, NULL, 0},
    {"fps_clamp",
     (const unsigned char *)"\x0F\x2F\x0F\x48\x0F\x47\xC7\x8B\x00\x89\x83\x00\x00\x00\x00",
     "xxxxxxxxxxx????", 15, NULL, 0},
    {"cutscene_je",
     (const unsigned char *)"\x74\x23\x48\x8B\x05\xCC\xCC\xCC\xCC\xF3\x0F\x10\x0D",
     "xxxxx????xxxx", 13, NULL, 0},
    {"refresh_60",
     (const unsigned char *)"\xC7\x45\x00\x3C\x00\x00\x00\xC7\x45\x00\x01\x00\x00\x00",
     "xx?x???xx?x???", 14, NULL, 0},
};
enum { SIG_SLEEP, SIG_CLAMP, SIG_CUTSCENE, SIG_REFRESH, SIG_COUNT };

static struct {
    int enabled;
    double cap;
    int cutscenes;
    int refresh;
    int timeout_ms;
} g_cfg = {1, 0.0, 1, 1, 60000};

static HMODULE g_self;
static HMODULE g_real;
static CRITICAL_SECTION g_log_cs;
static HANDLE g_log = INVALID_HANDLE_VALUE;
static wchar_t g_dir[MAX_PATH];

static void log_msg(const char *fmt, ...)
{
    char buf[1024];
    SYSTEMTIME t;
    va_list ap;
    int n;
    DWORD w;

    if (g_log == INVALID_HANDLE_VALUE)
        return;
    GetLocalTime(&t);
    n = _snprintf(buf, sizeof(buf), "[%02u:%02u:%02u.%03u] ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    va_start(ap, fmt);
    n += _vsnprintf(buf + n, sizeof(buf) - n - 2, fmt, ap);
    va_end(ap);
    if (n < 0 || n > (int)sizeof(buf) - 2)
        n = sizeof(buf) - 2;
    buf[n++] = '\r';
    buf[n++] = '\n';
    EnterCriticalSection(&g_log_cs);
    WriteFile(g_log, buf, n, &w, NULL);
    LeaveCriticalSection(&g_log_cs);
}

static void hexdump(const char *what, const unsigned char *p, size_t n)
{
    char s[3 * 32 + 1];
    size_t i;
    for (i = 0; i < n && i < 32; i++)
        _snprintf(s + 3 * i, 4, "%02X ", p[i]);
    s[3 * i] = 0;
    log_msg("  %s: %s", what, s);
}

static const char *getcfg(const char *env1, const char *env2, const char *key, char *buf, DWORD len)
{
    wchar_t ini[MAX_PATH];
    wchar_t wkey[64];
    wchar_t wval[64];
    DWORD n;

    if ((n = GetEnvironmentVariableA(env1, buf, len)) && n < len)
        return buf;
    if ((n = GetEnvironmentVariableA(env2, buf, len)) && n < len)
        return buf;
    _snwprintf(ini, MAX_PATH, L"%ls\\sonicfps.ini", g_dir);
    MultiByteToWideChar(CP_ACP, 0, key, -1, wkey, 64);
    n = GetPrivateProfileStringW(L"sonicfps", wkey, L"", wval, 64, ini);
    if (n) {
        WideCharToMultiByte(CP_ACP, 0, wval, -1, buf, len, NULL, NULL);
        return buf;
    }
    return NULL;
}

static void load_config(void)
{
    char b[64];
    const char *v;

    if ((v = getcfg("STEAMBRIDGE_SONICFPS", "SONICFPS", "enabled", b, sizeof(b))))
        g_cfg.enabled = atoi(v) != 0;
    if ((v = getcfg("STEAMBRIDGE_SONICFPS_CAP", "SONICFPS_CAP", "cap", b, sizeof(b)))) {
        double c = strtod(v, NULL);
        g_cfg.cap = (c > 0.0 && c <= 1000.0) ? c : 0.0;
    }
    if ((v = getcfg("STEAMBRIDGE_SONICFPS_CUTSCENES", "SONICFPS_CUTSCENES", "cutscenes", b, sizeof(b))))
        g_cfg.cutscenes = atoi(v) != 0;
    if ((v = getcfg("STEAMBRIDGE_SONICFPS_REFRESH", "SONICFPS_REFRESH", "refresh", b, sizeof(b))))
        g_cfg.refresh = atoi(v) != 0;
    if ((v = getcfg("STEAMBRIDGE_SONICFPS_TIMEOUT", "SONICFPS_TIMEOUT", "timeout_ms", b, sizeof(b))))
        g_cfg.timeout_ms = atoi(v);
}

static int readable(DWORD prot)
{
    if (prot & (PAGE_GUARD | PAGE_NOACCESS))
        return 0;
    return (prot & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ |
                    PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) != 0;
}

static unsigned char *scan_range(unsigned char *start, unsigned char *end, const Sig *s)
{
    unsigned char *p, *last;
    size_t i;

    if ((size_t)(end - start) < s->len)
        return NULL;
    last = end - s->len;
    for (p = start; p <= last; p++) {
        if (*p != s->pat[0])
            continue;
        for (i = 1; i < s->len; i++)
            if (s->mask[i] == 'x' && p[i] != s->pat[i])
                break;
        if (i == s->len)
            return p;
    }
    return NULL;
}

static unsigned char *scan_mem(unsigned char *start, unsigned char *end, const Sig *s, unsigned char **resume)
{
    unsigned char *p = start;

    while (p < end) {
        MEMORY_BASIC_INFORMATION mbi;
        unsigned char *run_end;
        unsigned char *hit;

        if (!VirtualQuery(p, &mbi, sizeof(mbi)))
            break;
        run_end = (unsigned char *)mbi.BaseAddress + mbi.RegionSize;
        if (run_end > end)
            run_end = end;
        if (mbi.State == MEM_COMMIT && readable(mbi.Protect)) {
            hit = scan_range(p, run_end, s);
            if (hit) {
                if (resume)
                    *resume = hit + 1;
                return hit;
            }
        }
        p = run_end;
    }
    return NULL;
}

static int find_sig(Sig *s)
{
    unsigned char *base = (unsigned char *)GetModuleHandleW(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
    WORD i;

    for (i = 0; i < nt->FileHeader.NumberOfSections; i++, sec++) {
        unsigned char *a, *b, *hit, *next;
        int dups = 0;

        if (!(sec->Characteristics & (IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_CNT_CODE)))
            continue;
        a = base + sec->VirtualAddress;
        b = a + (sec->Misc.VirtualSize ? sec->Misc.VirtualSize : sec->SizeOfRawData);
        hit = scan_mem(a, b, s, &next);
        if (!hit)
            continue;
        while (scan_mem(next, b, s, &next))
            dups++;
        s->addr = hit;
        log_msg("found %s at %p (rva 0x%llx, section %.8s)%s", s->name, hit,
             (unsigned long long)(hit - base), (const char *)sec->Name,
             dups ? " WARNING: more matches in this section, using first" : "");
        return 1;
    }
    return 0;
}

static int write_code(unsigned char *dst, const void *src, size_t n)
{
    DWORD old, tmp;

    if (!VirtualProtect(dst, n, PAGE_EXECUTE_READWRITE, &old)) {
        log_msg("  VirtualProtect(%p) failed: %lu", dst, GetLastError());
        return 0;
    }
    memcpy(dst, src, n);
    VirtualProtect(dst, n, old, &tmp);
    FlushInstructionCache(GetCurrentProcess(), dst, n);
    return 1;
}

static int apply(int idx)
{
    Sig *s = &g_sigs[idx];
    unsigned char *p = s->addr;
    unsigned char buf[16];

    hexdump("before", p, s->len);
    switch (idx) {
    case SIG_SLEEP:
        if (g_cfg.cap > 0.0) {
            log_msg("  cap mode: limiter sleep kept");
            return 1;
        }
        memset(buf, 0x90, 5);
        if (!write_code(p, buf, 5))
            return 0;
        break;
    case SIG_CLAMP:
        if (g_cfg.cap > 0.0) {
            float f = (float)g_cfg.cap;
            buf[0] = 0xC7;
            buf[1] = 0x07;
            memcpy(buf + 2, &f, 4);
            memset(buf + 6, 0x90, 9);
        } else {
            buf[0] = 0x8B;
            buf[1] = 0x00;
            memcpy(buf + 2, p + 9, 6);
            buf[8] = 0x89;
            buf[9] = 0x07;
            memset(buf + 10, 0x90, 5);
        }
        if (!write_code(p, buf, 15))
            return 0;
        break;
    case SIG_CUTSCENE:
        if (!g_cfg.cutscenes) {
            log_msg("  cutscene patch disabled by config");
            return 1;
        }
        buf[0] = 0xEB;
        if (!write_code(p, buf, 1))
            return 0;
        break;
    case SIG_REFRESH:
        if (!g_cfg.refresh) {
            log_msg("  refresh patch disabled by config");
            return 1;
        }
        buf[0] = 0;
        if (!write_code(p + 3, buf, 1) || !write_code(p + 10, buf, 1))
            return 0;
        break;
    }
    hexdump("after ", p, s->len);
    return 1;
}

static int pass(void)
{
    int i, left = 0;

    for (i = 0; i < SIG_COUNT; i++) {
        if (g_sigs[i].done)
            continue;
        if (!g_sigs[i].addr && !find_sig(&g_sigs[i])) {
            left++;
            continue;
        }
        g_sigs[i].done = apply(i) ? 1 : -1;
    }
    return left;
}

static DWORD WINAPI retry_thread(void *arg)
{
    DWORD t0 = GetTickCount();
    int i, left;

    (void)arg;
    for (;;) {
        Sleep(250);
        left = pass();
        if (!left) {
            log_msg("all patches applied after %lu ms", GetTickCount() - t0);
            return 0;
        }
        if ((int)(GetTickCount() - t0) > g_cfg.timeout_ms)
            break;
    }
    for (i = 0; i < SIG_COUNT; i++)
        if (!g_sigs[i].done)
            log_msg("GAVE UP: %s not found (game version mismatch?)", g_sigs[i].name);
    return 0;
}

static void init(void)
{
    wchar_t path[MAX_PATH];
    wchar_t *slash;

    InitializeCriticalSection(&g_log_cs);
    GetModuleFileNameW(NULL, g_dir, MAX_PATH);
    slash = wcsrchr(g_dir, L'\\');
    if (slash)
        *slash = 0;
    _snwprintf(path, MAX_PATH, L"%ls\\sonicfps.log", g_dir);
    g_log = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);

    load_config();
    log_msg("sonicfps loaded (enabled=%d cap=%s%.1f cutscenes=%d refresh=%d timeout_ms=%d)",
         g_cfg.enabled, g_cfg.cap > 0.0 ? "" : "unlimited/", g_cfg.cap, g_cfg.cutscenes, g_cfg.refresh,
         g_cfg.timeout_ms);
    if (!g_cfg.enabled) {
        log_msg("disabled by config, only forwarding dinput8");
        return;
    }
    if (pass() == 0) {
        log_msg("all patches applied at load");
        return;
    }
    log_msg("some signatures not found yet, polling in background");
    CloseHandle(CreateThread(NULL, 0, retry_thread, NULL, 0, NULL));
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = inst;
        DisableThreadLibraryCalls(inst);
        init();
    }
    return TRUE;
}

static FARPROC real(const char *name)
{
    if (!g_real) {
        wchar_t path[MAX_PATH];
        UINT n = GetSystemDirectoryW(path, MAX_PATH);
        HMODULE h;

        _snwprintf(path + n, MAX_PATH - n, L"\\dinput8.dll");
        h = LoadLibraryW(path);
        if (!h || h == g_self) {
            log_msg("cannot load system dinput8 from %ls (err %lu)", path, GetLastError());
            return NULL;
        }
        g_real = h;
        log_msg("forwarding to %ls", path);
    }
    return GetProcAddress(g_real, name);
}

typedef HRESULT(WINAPI *pDirectInput8Create)(HINSTANCE, DWORD, const GUID *, void **, void *);
typedef HRESULT(WINAPI *pDllGetClassObject)(const GUID *, const GUID *, void **);
typedef HRESULT(WINAPI *pVoidHr)(void);
typedef const void *(WINAPI *pGetdf)(void);

HRESULT WINAPI proxy_DirectInput8Create(HINSTANCE h, DWORD v, const GUID *riid, void **out, void *outer)
{
    pDirectInput8Create f = (pDirectInput8Create)(void *)real("DirectInput8Create");
    return f ? f(h, v, riid, out, outer) : E_FAIL;
}

HRESULT WINAPI proxy_DllGetClassObject(const GUID *clsid, const GUID *riid, void **out)
{
    pDllGetClassObject f = (pDllGetClassObject)(void *)real("DllGetClassObject");
    return f ? f(clsid, riid, out) : E_FAIL;
}

HRESULT WINAPI proxy_DllCanUnloadNow(void)
{
    pVoidHr f = (pVoidHr)(void *)real("DllCanUnloadNow");
    return f ? f() : S_FALSE;
}

HRESULT WINAPI proxy_DllRegisterServer(void)
{
    pVoidHr f = (pVoidHr)(void *)real("DllRegisterServer");
    return f ? f() : E_FAIL;
}

HRESULT WINAPI proxy_DllUnregisterServer(void)
{
    pVoidHr f = (pVoidHr)(void *)real("DllUnregisterServer");
    return f ? f() : E_FAIL;
}

const void *WINAPI proxy_GetdfDIJoystick(void)
{
    pGetdf f = (pGetdf)(void *)real("GetdfDIJoystick");
    return f ? f() : NULL;
}
