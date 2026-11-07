#ifndef SHOUYI_NEARLINK_BRIDGE_H
#define SHOUYI_NEARLINK_BRIDGE_H
#include <stdbool.h>
#include <stddef.h>
void nearlink_bridge_init(void);
bool nearlink_bridge_motion(void);
bool nearlink_bridge_online(void);
/* -2: no link, -1: warming, 0: idle, 1: motion */
int nearlink_bridge_pir_state(void);
void nearlink_bridge_status(char *text, size_t size);
#endif
