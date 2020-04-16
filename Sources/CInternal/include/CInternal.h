//
//  font.h
//  GFXTest
//
//  Created by Simon Evans on 09/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//

#ifndef font_h
#define font_h

struct font_desc {
    int idx;
    const char *name;
    int width, height;
    const void *data;
    int pref;
};


extern const struct font_desc font_vga_8x16;

#endif /* font_h */
