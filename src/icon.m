#import <AppKit/AppKit.h>

// Usage: icontool <out.png> [source.png]
// Renders a 1024×1024 macOS app icon: Apple's rounded-square shape (824×824 centred, radius ~185),
// transparent outside. With a source PNG, the artwork is scaled to fill and clipped to that shape;
// without one, a DeepSeek-blue square with a whale emoji is drawn (the default icon).
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: icontool <out.png> [source.png]\n"); return 2; }
        NSSize size = NSMakeSize(1024, 1024);
        NSRect squircle = NSInsetRect(NSMakeRect(0, 0, 1024, 1024), 100, 100);
        NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:squircle xRadius:185 yRadius:185];
        NSImage *img = [[NSImage alloc] initWithSize:size];
        [img lockFocus];
        [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;
        if (argc >= 3) {
            NSImage *src = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
            if (!src) { fprintf(stderr, "icontool: cannot read %s\n", argv[2]); return 1; }
            [NSGraphicsContext saveGraphicsState];
            [shape addClip];
            [src drawInRect:squircle fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
            [NSGraphicsContext restoreGraphicsState];
        } else {
            [[NSColor colorWithCalibratedRed:0.106 green:0.318 blue:0.933 alpha:1.0] setFill];
            [shape fill];
            NSAttributedString *text = [[NSAttributedString alloc]
                initWithString:@"\U0001F40B" attributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:540] }];
            NSSize tsize = [text size];
            [text drawAtPoint:NSMakePoint((size.width - tsize.width) / 2, (size.height - tsize.height) / 2 + 10)];
        }
        [img unlockFocus];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
        printf("icon written\n");
    }
    return 0;
}
