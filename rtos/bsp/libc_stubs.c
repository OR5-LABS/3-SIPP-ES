/* Freestanding libc stubs pulled in by the FreeRTOS kernel (queue/task). */
#include <stddef.h>

void *memcpy( void *d, const void *s, size_t n )
{
    unsigned char *dd = d;
    const unsigned char *ss = s;
    while( n-- ) *dd++ = *ss++;
    return d;
}

void *memset( void *d, int c, size_t n )
{
    unsigned char *dd = d;
    while( n-- ) *dd++ = (unsigned char) c;
    return d;
}

void *memmove( void *d, const void *s, size_t n )
{
    unsigned char *dd = d;
    const unsigned char *ss = s;
    if( dd < ss )
        while( n-- ) *dd++ = *ss++;
    else
    {
        dd += n; ss += n;
        while( n-- ) *--dd = *--ss;
    }
    return d;
}

int memcmp( const void *s1, const void *s2, size_t n )
{
    const unsigned char *p1 = s1, *p2 = s2;
    while( n-- )
    {
        if( *p1 != *p2 ) return *p1 - *p2;
        p1++; p2++;
    }
    return 0;
}

char *strncpy( char *d, const char *s, size_t n )
{
    char *dest = d;
    while( n && *s ) { *d++ = *s++; n--; }
    while( n-- ) { *d++ = '\0'; }
    return dest;
}

size_t strlen( const char *s )
{
    size_t len = 0;
    while( s[ len ] ) len++;
    return len;
}
