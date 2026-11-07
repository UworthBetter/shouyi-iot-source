#ifndef SHOUYI_NEARLINK_PROTOCOL_H
#define SHOUYI_NEARLINK_PROTOCOL_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define NL_FRAME_SIZE 192
#define NL_STALE_MS 10000U
typedef struct {
    char line[NL_FRAME_SIZE];
    size_t used;
    bool dropping;
    bool seen;
    bool ready;
    bool pir;
    uint32_t seq;
    uint32_t received_ms;
    uint32_t accepted;
    uint32_t rejected;
} nl_state;

/* Call feed and query from one owner task; now_ms is a monotonic uint32 clock. */
void nl_feed(nl_state *state, const uint8_t *bytes, size_t length, uint32_t now_ms);
bool nl_online(const nl_state *state, uint32_t now_ms);
bool nl_motion(const nl_state *state, uint32_t now_ms);
#endif
