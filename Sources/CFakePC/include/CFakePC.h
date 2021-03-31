//
//  header.h
//  FakePC
//
//  Created by Simon Evans on 09/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//

#define _XOPEN_SOURCE_EXTENDED 1
#define NCURSES_WIDECHAR 1
#define NCURSES_NOMACROS

#ifndef _CFAKEPC_H
#define _CFAKEPC_H


#import <curses.h>

struct font_desc {
    int idx;
    const char *name;
    int width, height;
    const void *data;
    int pref;
};


extern const struct font_desc font_vga_8x16;

#ifndef CCHARW_MAX

#define CCHARW_MAX      5
typedef struct
{
    attr_t      attr;
    wchar_t     chars[CCHARW_MAX];
}
cchar_t;
#endif

extern const cchar_t codepage437_characters[256];

static inline
const cchar_t *cp437Character(uint8_t ch) {
    return &codepage437_characters[ch];
}

extern int mvadd_wch (int, int, const cchar_t *);
static inline
int writeCharAtRowColumn(int row, int column, uint8_t ch) {
    return mvadd_wch(row, column, &codepage437_characters[ch]);
}

#endif /* _CFAKEPC_H */
