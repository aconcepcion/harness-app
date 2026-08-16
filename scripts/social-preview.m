#import <AppKit/AppKit.h>
// Build: clang -fobjc-arc -o build/social scripts/social-preview.m -framework AppKit
// Run:   build/icontool build/icon-masked.png Resources/AppIcon-1024.png && build/social build/icon-masked.png docs/img/social-preview.png Resources/AppIcon-1024.png && sips -z 640 1280 docs/img/social-preview.png --out docs/img/social-preview.png
// Renders a 1280x640 GitHub social-preview card: green field, masked icon left, black text right.
int main(int argc, const char *argv[]) { @autoreleasepool {
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(1280, 640)];
    [img lockFocus];
    [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;
    NSBitmapImageRep *srcRep = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[3]]]];
    NSColor *field = [[srcRep colorAtX:8 y:8] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    field = [NSColor colorWithSRGBRed:field.redComponent*0.90 green:field.greenComponent*0.92 blue:field.blueComponent*0.90 alpha:1];
    [field setFill];
    NSRectFill(NSMakeRect(0, 0, 1280, 640));
    // icon (already masked, transparent corners) at left
    NSShadow *sh = [NSShadow new]; sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.28]; sh.shadowBlurRadius = 28; sh.shadowOffset = NSMakeSize(0, -10);
    [NSGraphicsContext saveGraphicsState]; [sh set];
    [icon drawInRect:NSMakeRect(96, 148, 344, 344) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    NSColor *ink = [NSColor colorWithSRGBRed:0.05 green:0.08 blue:0.05 alpha:1];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineSpacing = 4;
    NSDictionary *h1 = @{NSFontAttributeName: [NSFont systemFontOfSize:78 weight:NSFontWeightBold], NSForegroundColorAttributeName: ink, NSParagraphStyleAttributeName: ps};
    NSDictionary *h2 = @{NSFontAttributeName: [NSFont systemFontOfSize:31 weight:NSFontWeightMedium], NSForegroundColorAttributeName: ink, NSParagraphStyleAttributeName: ps};
    NSDictionary *h3 = @{NSFontAttributeName: [NSFont monospacedSystemFontOfSize:22 weight:NSFontWeightRegular], NSForegroundColorAttributeName: [ink colorWithAlphaComponent:0.75]};
    [@"Harness.app" drawAtPoint:NSMakePoint(500, 400) withAttributes:h1];
    [@"Your own DeepSeek Harness (dsh)\nin a native Mac window." drawInRect:NSMakeRect(500, 250, 720, 130) withAttributes:h2];
    [@"~1,200 lines of Objective-C · no Electron\nno bundled dsh · no tray · MIT" drawInRect:NSMakeRect(500, 150, 720, 80) withAttributes:h3];
    [img unlockFocus];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
    return 0;
} }
