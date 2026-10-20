/* Freestanding string.h for bare-metal Dhrystone build */
#ifndef _DHRY_STRING_H
#define _DHRY_STRING_H

#include <stddef.h>

char *strcpy(char *dest, const char *src);
int   strcmp(const char *s1, const char *s2);

#endif /* _DHRY_STRING_H */
