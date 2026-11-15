@interface ZhengxinSearchButton : NSButton
@property BOOL pointerInside;
@property NSTrackingArea *hoverTrackingArea;
@end

@implementation ZhengxinSearchButton
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTrackingArea) [self removeTrackingArea:self.hoverTrackingArea];
    self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:self.hoverTrackingArea];
    NSPoint point = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    self.pointerInside = NSPointInRect(point, self.bounds);
    self.needsDisplay = YES;
}
- (void)mouseEntered:(NSEvent *)event { self.pointerInside = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.pointerInside = NO; self.needsDisplay = YES; }
- (void)highlight:(BOOL)flag { [super highlight:flag]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *color = (self.pointerInside || self.highlighted)
        ? [NSColor colorWithSRGBRed:206.0/255 green:186.0/255 blue:123.0/255 alpha:1]
        : [NSColor colorWithSRGBRed:42.0/255 green:63.0/255 blue:82.0/255 alpha:1];
    NSImage *tinted = [NSImage imageWithSize:self.image.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [self.image drawInRect:rect];
        [color setFill];
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceIn);
        return YES;
    }];
    NSRect rect = NSMakeRect((NSWidth(self.bounds) - 14) / 2, (NSHeight(self.bounds) - 14) / 2, 14, 14);
    [tinted drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
        fraction:self.enabled ? 1 : 0.4 respectFlipped:YES hints:nil];
}
@end

// Vector outline from the user-provided search.svg (31.51 × 31.51).
static NSButton *ZhengxinPathSearchButton(id target, SEL action, NSString *label) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(14, 14) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleBy:14.0 / 31.51];
        [transform concat];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(30.2500, 0.0300)];
        [path lineToPoint:NSMakePoint(29.7000, 0.0300)];
        [path curveToPoint:NSMakePoint(28.6700, 0.7300) controlPoint1:NSMakePoint(29.2700, 0.1400) controlPoint2:NSMakePoint(28.9900, 0.4000)];
        [path lineToPoint:NSMakePoint(21.9300, 7.4700)];
        [path curveToPoint:NSMakePoint(7.7300, 5.8300) controlPoint1:NSMakePoint(17.9200, 4.2800) controlPoint2:NSMakePoint(12.4800, 3.5900)];
        [path curveToPoint:NSMakePoint(0.0800, 16.8900) controlPoint1:NSMakePoint(3.5100, 7.8200) controlPoint2:NSMakePoint(0.4700, 12.0500)];
        [path lineToPoint:NSMakePoint(0.0300, 17.1100)];
        [path lineToPoint:NSMakePoint(0.0500, 18.8600)];
        [path curveToPoint:NSMakePoint(14.3000, 31.4600) controlPoint1:NSMakePoint(0.5700, 26.3000) controlPoint2:NSMakePoint(6.8800, 31.8700)];
        [path curveToPoint:NSMakePoint(25.6200, 23.9100) controlPoint1:NSMakePoint(19.2100, 31.1900) controlPoint2:NSMakePoint(23.5500, 28.1800)];
        [path curveToPoint:NSMakePoint(24.0400, 9.6000) controlPoint1:NSMakePoint(27.9100, 19.1800) controlPoint2:NSMakePoint(27.2800, 13.6800)];
        [path lineToPoint:NSMakePoint(31.0000, 2.6400)];
        [path curveToPoint:NSMakePoint(31.4000, 1.0400) controlPoint1:NSMakePoint(31.4400, 2.2000) controlPoint2:NSMakePoint(31.6000, 1.6400)];
        [path curveToPoint:NSMakePoint(30.2600, 0.0400) controlPoint1:NSMakePoint(31.2400, 0.5600) controlPoint2:NSMakePoint(30.8000, 0.1600)];
        [path closePath];
        [path moveToPoint:NSMakePoint(23.9900, 18.0000)];
        [path curveToPoint:NSMakePoint(13.5100, 28.4800) controlPoint1:NSMakePoint(23.9900, 23.7900) controlPoint2:NSMakePoint(19.3000, 28.4800)];
        [path curveToPoint:NSMakePoint(3.0300, 18.0000) controlPoint1:NSMakePoint(7.7200, 28.4800) controlPoint2:NSMakePoint(3.0300, 23.7900)];
        [path curveToPoint:NSMakePoint(13.5100, 7.5200) controlPoint1:NSMakePoint(3.0300, 12.2100) controlPoint2:NSMakePoint(7.7200, 7.5200)];
        [path curveToPoint:NSMakePoint(23.9900, 18.0000) controlPoint1:NSMakePoint(19.3000, 7.5200) controlPoint2:NSMakePoint(23.9900, 12.2100)];
        [path closePath];
        [[NSColor blackColor] setFill];
        [path fill];
        return YES;
    }];
    image.template = NO;
    NSButton *button = [[ZhengxinSearchButton alloc] initWithFrame:NSMakeRect(666, 0, 30, 30)];
    button.bordered = NO;
    button.image = image;
    button.imagePosition = NSImageOnly;
    button.contentTintColor = [NSColor colorWithSRGBRed:42.0/255 green:63.0/255 blue:82.0/255 alpha:1];
    button.target = target;
    button.action = action;
    button.toolTip = label;
    button.accessibilityLabel = label;
    button.autoresizingMask = NSViewMinXMargin;
    return button;
}
