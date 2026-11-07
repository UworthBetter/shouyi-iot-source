#include "nearlink_protocol.h"
#include "cJSON.h"
#include <string.h>

static bool parse_frame(nl_state *s, uint32_t now_ms)
{
    /* Terminal reports are flat objects. Bound parser stack use even when a
     * damaged UART line happens to contain deeply nested JSON. Brackets and
     * extra braces are not part of any supported field value. */
    const char *start = s->line;
    while (*start == ' ' || *start == '\t' || *start == '\r') { ++start; }
    if (*start != '{' || strchr(start + 1, '{') != NULL ||
        strchr(start, '[') != NULL || strchr(start, ']') != NULL) {
        return false;
    }
    cJSON *root = cJSON_ParseWithOpts(s->line, NULL, 1);
    bool valid = false;
    if (root == NULL) { return false; }
    cJSON *dev = cJSON_GetObjectItemCaseSensitive(root, "dev");
    cJSON *seq = cJSON_GetObjectItemCaseSensitive(root, "seq");
    cJSON *pir = cJSON_GetObjectItemCaseSensitive(root, "pir");
    cJSON *ready = cJSON_GetObjectItemCaseSensitive(root, "pirReady");
    /* Reject duplicate keys and unexpected fields, rather than choosing one. */
    if (cJSON_IsObject(root) && cJSON_GetArraySize(root) == 4 &&
        cJSON_IsString(dev) && strcmp(dev->valuestring, "sy-t-001") == 0 &&
        cJSON_IsNumber(seq) && seq->valuedouble >= 0 &&
        seq->valuedouble <= 4294967295.0 &&
        seq->valuedouble == (double)(uint32_t)seq->valuedouble &&
        cJSON_IsBool(pir) && cJSON_IsBool(ready)) {
        uint32_t number = (uint32_t)seq->valuedouble;
        /* A repeated notification must not keep a disconnected sensor alive.
         * Lower numbers are allowed: terminal reboot restarts its counter. */
        if (!s->seen || number != s->seq) {
            s->seen = true;
            s->seq = number;
            s->ready = cJSON_IsTrue(ready);
            s->pir = cJSON_IsTrue(pir);
            s->received_ms = now_ms;
            s->accepted++;
            valid = true;
        }
    }
    cJSON_Delete(root);
    return valid;
}

void nl_feed(nl_state *s, const uint8_t *bytes, size_t length, uint32_t now_ms)
{
    for (size_t i = 0; i < length; ++i) {
        uint8_t ch = bytes[i];
        if (ch == '\n') {
            if (!s->dropping && s->used > 0) {
                s->line[s->used] = '\0';
                if (!parse_frame(s, now_ms)) { s->rejected++; }
            }
            s->used = 0;
            s->dropping = false;
        } else if (ch == 0 || s->used >= sizeof(s->line) - 1) {
            if (!s->dropping) { s->rejected++; }
            s->dropping = true;
        } else if (!s->dropping) {
            s->line[s->used++] = (char)ch;
        }
    }
}

bool nl_online(const nl_state *s, uint32_t now_ms)
{
    return s->seen && (uint32_t)(now_ms - s->received_ms) < NL_STALE_MS;
}

bool nl_motion(const nl_state *s, uint32_t now_ms)
{
    return nl_online(s, now_ms) && s->ready && s->pir;
}
