#ifndef STEAMBRIDGE_FEATS_WEBPATCH_H
#define STEAMBRIDGE_FEATS_WEBPATCH_H

#include <stddef.h>
#include <stdint.h>

int sb_webpatch_should_patch(const char *path);

#define SB_SHAPE_FORCETOOL  "forcetool"
#define SB_SHAPE_SELECTTOOL "selecttool"

char *sb_webpatch_transform(const uint8_t *src, size_t src_len, size_t *out_len,
                            const char **out_shape);

#endif
