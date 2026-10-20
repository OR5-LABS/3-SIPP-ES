/* Freestanding string.h for 3-SIPP-ESR bare-metal RTOS builds */
#ifndef _FREESTANDING_STRING_H
#define _FREESTANDING_STRING_H

#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
void *memmove(void *dest, const void *src, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);
char *strncpy(char *dest, const char *src, size_t n);
size_t strlen(const char *s);

#endif /* _FREESTANDING_STRING_H */
