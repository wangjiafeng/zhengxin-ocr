#import <Cocoa/Cocoa.h>
#import "../ZhengxinMarkdownHelp.h"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *markdown = [NSString stringWithContentsOfFile:@"work/ZhengxinOCRUniversal/Resources/正心OCR帮助.md" encoding:NSUTF8StringEncoding error:nil];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,760,760)];
    scroll.hasVerticalScroller = YES;
    ZhengxinHelpDocumentView *doc = [[ZhengxinHelpDocumentView alloc] initWithMarkdown:markdown];
    doc.frame = NSMakeRect(0,0,scroll.contentSize.width,scroll.contentSize.height);
    scroll.documentView = doc;
    [doc updateDocumentGeometry];
    [scroll layoutSubtreeIfNeeded];
    NSString *collapsed = doc.helpTextView.string;
    NSArray *titles = @[@"所需环境与下载地址", @"所需模型与下载地址", @"办法一：下载安装（通过界面完成）", @"办法二：终端安装"];
    NSArray *bodyMarkers = @[@"无须先安装 Homebrew", @"PP-OCRv6 官方模型合集", @"通用版模型根目录", @"sudo /usr/sbin/installer"];
    if ([collapsed containsString:@"<details>"] || [collapsed containsString:@"sudo /usr/sbin/installer"]) return 5;
    if ([collapsed rangeOfString:@"安装说明"].location > [collapsed rangeOfString:titles[0]].location) return 6;
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSString *heading = [titles[i] stringByAppendingString:@"  +"];
        NSRange range = [doc.helpTextView.string rangeOfString:heading];
        if (range.location == NSNotFound) return 7;
        NSURL *link = [doc.helpTextView.textStorage attribute:NSLinkAttributeName atIndex:range.location effectiveRange:NULL];
        if (!link) return 8;
        [doc textView:doc.helpTextView clickedOnLink:link atIndex:range.location];
        if (![doc.helpTextView.string containsString:bodyMarkers[i]] || ![doc.helpTextView.string containsString:[titles[i] stringByAppendingString:@"  —"]]) return 9;
        [doc textView:doc.helpTextView clickedOnLink:link atIndex:range.location];
        if (![doc.helpTextView.string isEqualToString:collapsed]) return 10;
    }
    // Verify the long, fully expanded document still scrolls after resizing.
    [doc.expandedSections addIndexesInRange:NSMakeRange(0,4)];
    [doc rebuildHelpContent];
    for (NSNumber *width in @[@760, @1200, @660, @760]) {
        [scroll setFrameSize:NSMakeSize(width.doubleValue,760)];
        [scroll layoutSubtreeIfNeeded];
        [doc layoutSubtreeIfNeeded];
        CGFloat height = doc.frame.size.height;
        CGFloat viewport = scroll.contentView.bounds.size.height;
        NSLog(@"width=%@ document=%.0f viewport=%.0f",width,height,viewport);
        if (height <= viewport) return 1;
        [doc.helpTextView.layoutManager ensureLayoutForTextContainer:doc.helpTextView.textContainer];
        NSRect used = [doc.helpTextView.layoutManager usedRectForTextContainer:doc.helpTextView.textContainer];
        if (height < ceil(NSMaxY(used) + 72)) return 4;
        [doc scrollPoint:NSMakePoint(0,height)];
        if (NSMaxY(scroll.contentView.bounds) < height - 1) return 2;
        [doc scrollPoint:NSZeroPoint];
        if (scroll.contentView.bounds.origin.y != 0) return 3;
    }
    return 0;
}}
