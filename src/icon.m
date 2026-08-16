#import <AppKit/AppKit.h>

// Render a DeepSeek-blue rounded-rect icon with a whale (DeepSeek's mark).
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSSize size = NSMakeSize(1024, 1024);
        NSImage *img = [[NSImage alloc] initWithSize:size];
        [img lockFocus];
        NSRect inset = NSInsetRect(NSMakeRect(0, 0, 1024, 1024), 100, 100);
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:inset
                                                             xRadius:185 yRadius:185];
        [[NSColor colorWithCalibratedRed:0.106 green:0.318 blue:0.933 alpha:1.0] setFill];
        [path fill];
        NSAttributedString *text = [[NSAttributedString alloc]
            initWithString:@"\U0001F40B"
                attributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:540] }];
        NSSize tsize = [text size];
        [text drawAtPoint:NSMakePoint((size.width - tsize.width) / 2,
                                      (size.height - tsize.height) / 2 + 10)];
        [img unlockFocus];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        printf("icon written\n");
    }
    return 0;
}
