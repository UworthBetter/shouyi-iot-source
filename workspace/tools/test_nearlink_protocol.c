#include "nearlink_protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void feed(nl_state *s, const char *text, uint32_t now)
{
    nl_feed(s, (const uint8_t *)text, strlen(text), now);
}

int main(void)
{
    const char *active = "{\"seq\":1,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":true}\r\n";
    /* A frame may arrive split at any byte, not only at JSON boundaries. */
    for (size_t split = 0; split <= strlen(active); ++split) {
        nl_state s = {0};
        nl_feed(&s, (const uint8_t *)active, split, 100);
        nl_feed(&s, (const uint8_t *)active + split, strlen(active) - split, 100);
        assert(s.accepted == 1 && nl_motion(&s, 100));
    }
    nl_state s = {0};
    assert(!nl_online(&s, 0) && !nl_motion(&s, 0));
    feed(&s, active, 100);
    assert(nl_motion(&s, 10099));
    assert(!nl_online(&s, 10100) && !nl_motion(&s, 10100));
    feed(&s, active, 20000);  /* duplicate must not refresh health */
    assert(s.accepted == 1 && !nl_online(&s, 20000));
    feed(&s, "{\"seq\":2,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":false}\n", 21000);
    assert(nl_online(&s, 21000) && !nl_motion(&s, 21000));
    feed(&s, "{\"seq\":3,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":true}\n"
             "{\"seq\":4,\"dev\":\"sy-t-001\",\"pir\":false,\"pirReady\":true}\n", 22000);
    assert(s.accepted == 4 && !nl_motion(&s, 22000));
    /* A reboot may restart seq at one. */
    feed(&s, active, 23000);
    assert(s.accepted == 5 && nl_motion(&s, 23000));
    uint32_t good = s.accepted;
    const char *bad[] = {
        "garbage\n", "{}\n",
        "{\"seq\":9,\"dev\":\"other\",\"pir\":true,\"pirReady\":true}\n",
        "{\"seq\":9,\"dev\":\"sy-t-001\",\"pir\":1,\"pirReady\":true}\n",
        "{\"seq\":9,\"dev\":\"sy-t-001\",\"pir\":true}\n",
        "{\"seq\":9,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":true}junk\n",
        "{\"seq\":9,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":true,\"pir\":false}\n",
        "{\"seq\":-1,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":true}\n",
        "{\"seq\":1.5,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":true}\n",
        "{\"seq\":4294967296,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":true}\n",
        "{\"seq\":9,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":{\"nested\":true}}\n",
    };
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i) { feed(&s, bad[i], 24000); }
    assert(s.accepted == good && s.received_ms == 23000);
    /* Oversize and embedded NUL discard the whole line, then recover. */
    char huge[400];
    memset(huge, 'x', sizeof(huge));
    nl_feed(&s, (const uint8_t *)huge, sizeof(huge), 25000);
    feed(&s, "\n", 25000);
    const uint8_t nul[] = {'x', 0, 'x', '\n'};
    nl_feed(&s, nul, sizeof(nul), 25000);
    assert(s.accepted == good);
    feed(&s, "{\"seq\":5,\"dev\":\"sy-t-001\",\"pir\":true,\"pirReady\":true}\n", 26000);
    assert(s.accepted == good + 1 && nl_motion(&s, 26000));
    nl_state rollover = {0};
    feed(&rollover, active, UINT32_MAX - 1000);
    assert(nl_online(&rollover, 2000) && !nl_online(&rollover, 10000));
    puts("PASS: all byte splits, joined frames, warmup, stale state, duplicates, reboot,");
    puts("      malformed data, overflow, NUL recovery, and clock rollover");
    return 0;
}
