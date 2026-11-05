#ifndef STEAMBRIDGE_FEATS_WEBUI_H
#define STEAMBRIDGE_FEATS_WEBUI_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>

int sb_webui_init(const struct mach_header_64 *mh, intptr_t slide,
                  uintptr_t register_fn, uintptr_t dispatch_fn,
                  uintptr_t send_response);

uintptr_t sb_webui_registry(void);

void sb_webui_dump_routes(void);

uintptr_t sb_webui_lookup_site(uintptr_t register_fn, uintptr_t dispatch_fn);

int sb_webui_parse_into(uintptr_t message, const void *bytes, uint32_t len);

uintptr_t sb_webui_new_message(uintptr_t vptr);

int sb_webui_notify(const char *name, uintptr_t message);

typedef int (*sb_webui_handler_fn)(uintptr_t request, uintptr_t response);

int sb_webui_register_route(const char *name, uintptr_t request_vptr,
                           uintptr_t response_vptr, sb_webui_handler_fn handler);

#endif
