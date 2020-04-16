//
//  ScreenMode.swift
//  FakePC
//
//  Created by Simon Evans on 16/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Data for the different video modes.
//



struct ScreenMode {
    
    enum Color {
        case monochrome
        case greyScale(Int)
        case color(Int)
    }
    
    let isTextMode: Bool
    let widthInPixels: Int
    let heightInPixels: Int
    let textRows: Int
    let textColumns: Int
    let textWidth: UInt8
    let textHeight: UInt16
    let vramSegment: UInt16
    let videoPageSize: UInt32
    let videoPageCount: Int
    let color: Color
    
    var isColor: Bool {
        switch color {
            case .monochrome: return false
            default: return true
        }
    }
    
    static func screenModeFor(mode: Int) -> ScreenMode? {
        let screenMode: ScreenMode
        
        switch mode {
            case 0x00:  //  40x25 Greyscale text (CGA,EGA,MCGA,VGA)
                screenMode = ScreenMode(isTextMode: true,
                                        widthInPixels: 360,
                                        heightInPixels: 400,
                                        textRows: 25,
                                        textColumns: 40,
                                        textWidth: 9,
                                        textHeight: 16,
                                        vramSegment: 0xB800,
                                        videoPageSize: 2048,
                                        videoPageCount: 8,
                                        color: .greyScale(16)
            )
            
            case 0x01:  //  40x25 16 color text (CGA,EGA,MCGA,VGA)
                screenMode = ScreenMode(isTextMode: true,
                                        widthInPixels: 360,
                                        heightInPixels: 400,
                                        textRows: 25,
                                        textColumns: 40,
                                        textWidth: 9,
                                        textHeight: 16,
                                        vramSegment: 0xB800,
                                        videoPageSize: 2048,
                                        videoPageCount: 8,
                                        color: .color(16)
            )
            
            case 0x02:  //  80x25 16 Greyscal text (CGA,EGA,MCGA,VGA)
                screenMode = ScreenMode(isTextMode: true,
                                        widthInPixels: 720,
                                        heightInPixels: 400,
                                        textRows: 25,
                                        textColumns: 80,
                                        textWidth: 9,
                                        textHeight: 16,
                                        vramSegment: 0xB800,
                                        videoPageSize: 2048,
                                        videoPageCount: 8,
                                        color: .greyScale(16)
            )
            
            case 0x03:  //  80x25 16 color text (CGA,EGA,MCGA,VGA)
                screenMode = ScreenMode(isTextMode: true,
                                        widthInPixels: 720,
                                        heightInPixels: 400,
                                        textRows: 25,
                                        textColumns: 80,
                                        textWidth: 9,
                                        textHeight: 16,
                                        vramSegment: 0xB800,
                                        videoPageSize: 2048,
                                        videoPageCount: 8,
                                        color: .color(16)
            )
            
            
            case 0x04:  //  320x200 4 color graphics (CGA,EGA,MCGA,VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 320,
                                        heightInPixels: 200,
                                        textRows: 25,
                                        textColumns: 40,
                                        textWidth: 8,
                                        textHeight: 8,
                                        vramSegment: 0xB800,
                                        videoPageSize: 16384,
                                        videoPageCount: 1,
                                        color: .color(4)
            )
            
            case 0x05:  //  320x200 4 color graphics (CGA,EGA,MCGA,VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 320,
                                        heightInPixels: 200,
                                        textRows: 25,
                                        textColumns: 40,
                                        textWidth: 8,
                                        textHeight: 8,
                                        vramSegment: 0xB800,
                                        videoPageSize: 16384,
                                        videoPageCount: 1,
                                        color: .color(4)
            )
            
            case 0x06:  //  640x200 B/W graphics (CGA,EGA,MCGA,VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 640,
                                        heightInPixels: 200,
                                        textRows: 25,
                                        textColumns: 80,
                                        textWidth: 8,
                                        textHeight: 8,
                                        vramSegment: 0xB800,
                                        videoPageSize: 16384,
                                        videoPageCount: 1,
                                        color: .monochrome
            )
            
            case 0x07:  //  80x25 Monochrome text (MDA,HERC,EGA,VGA)
                screenMode = ScreenMode(isTextMode: true,
                                        widthInPixels: 720,
                                        heightInPixels: 400,
                                        textRows: 25,
                                        textColumns: 80,
                                        textWidth: 9,
                                        textHeight: 16,
                                        vramSegment: 0xB000,
                                        videoPageSize: 2048,
                                        videoPageCount: 8,
                                        color: .monochrome
            )
            
            case 0x0D:  //  320x200 16 color graphics (EGA,VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 320,
                                        heightInPixels: 200,
                                        textRows: 25,
                                        textColumns: 40,
                                        textWidth: 8,
                                        textHeight: 8,
                                        vramSegment: 0xA000,
                                        videoPageSize: 32768,
                                        videoPageCount: 8,
                                        color: .color(16)
            )
            
            case 0x0E:  //  640x200 16 color graphics (EGA,VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 640,
                                        heightInPixels: 200,
                                        textRows: 25,
                                        textColumns: 80,
                                        textWidth: 8,
                                        textHeight: 8,
                                        vramSegment: 0xA000,
                                        videoPageSize: 65536,
                                        videoPageCount: 4,
                                        color: .color(16)
            )
            
            case 0x0F:  //  640x350 Monochrome graphics (EGA,VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 640,
                                        heightInPixels: 350,
                                        textRows: 25,
                                        textColumns: 80,
                                        textWidth: 8,
                                        textHeight: 14,
                                        vramSegment: 0xA000,
                                        videoPageSize: 32768,
                                        videoPageCount: 2,
                                        color: .monochrome
            )
            
            case 0x10:  //  640x350 16 color graphics (EGA or VGA with 128K)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 640,
                                        heightInPixels: 350,
                                        textRows: 25,
                                        textColumns: 80,
                                        textWidth: 8,
                                        textHeight: 14,
                                        vramSegment: 0xA000,
                                        videoPageSize: 131072,
                                        videoPageCount: 2,
                                        color: .color(16)
            )
            
            case 0x11:  //  640x480 B/W graphics (MCGA,VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 640,
                                        heightInPixels: 480,
                                        textRows: 30,
                                        textColumns: 80,
                                        textWidth: 8,
                                        textHeight: 16,
                                        vramSegment: 0xA000,
                                        videoPageSize: 65536,
                                        videoPageCount: 1,
                                        color: .monochrome
            )
            
            case 0x12:  //  640x480 16 color graphics (VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 640,
                                        heightInPixels: 480,
                                        textRows: 30,
                                        textColumns: 80,
                                        textWidth: 8,
                                        textHeight: 16,
                                        vramSegment: 0xA000,
                                        videoPageSize: 262144,
                                        videoPageCount: 1,
                                        color: .color(16)
            )
            case 0x13:  //  320x200 256 color graphics (MCGA,VGA)
                screenMode = ScreenMode(isTextMode: false,
                                        widthInPixels: 320,
                                        heightInPixels: 200,
                                        textRows: 25,
                                        textColumns: 40,
                                        textWidth: 8,
                                        textHeight: 8,
                                        vramSegment: 0xA000,
                                        videoPageSize: 65536,
                                        videoPageCount: 1,
                                        color: .color(256)
            )
            default: return nil
        }
        return screenMode
    }
}
