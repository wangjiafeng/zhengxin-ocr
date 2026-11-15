#import <Cocoa/Cocoa.h>

static NSFont *ZhengxinHelpFont(CGFloat size, NSFontWeight weight) {
    return [NSFont systemFontOfSize:size weight:weight];
}

static void ZhengxinAppendInlineMarkdown(NSMutableAttributedString *target,
                                         NSString *source,
                                         NSDictionary<NSAttributedStringKey, id> *baseAttributes) {
    NSUInteger cursor = 0;
    while (cursor < source.length) {
        NSRange searchRange = NSMakeRange(cursor, source.length - cursor);
        NSRange boldStart = [source rangeOfString:@"**" options:0 range:searchRange];
        NSRange linkStart = [source rangeOfString:@"[" options:0 range:searchRange];
        BOOL hasBold = boldStart.location != NSNotFound;
        BOOL hasLink = linkStart.location != NSNotFound;
        NSUInteger next = source.length;
        if (hasBold) next = MIN(next, boldStart.location);
        if (hasLink) next = MIN(next, linkStart.location);
        if (next > cursor) {
            [target appendAttributedString:[[NSAttributedString alloc] initWithString:[source substringWithRange:NSMakeRange(cursor, next - cursor)] attributes:baseAttributes]];
            cursor = next;
            continue;
        }
        if (hasBold && boldStart.location == cursor) {
            NSRange endSearch = NSMakeRange(cursor + 2, source.length - cursor - 2);
            NSRange boldEnd = [source rangeOfString:@"**" options:0 range:endSearch];
            if (boldEnd.location != NSNotFound) {
                NSString *text = [source substringWithRange:NSMakeRange(cursor + 2, boldEnd.location - cursor - 2)];
                NSMutableDictionary *attributes = [baseAttributes mutableCopy];
                NSFont *baseFont = baseAttributes[NSFontAttributeName] ?: ZhengxinHelpFont(14, NSFontWeightRegular);
                attributes[NSFontAttributeName] = [[NSFontManager sharedFontManager] convertFont:baseFont toHaveTrait:NSBoldFontMask];
                [target appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
                cursor = NSMaxRange(boldEnd);
                continue;
            }
        }
        if (hasLink && linkStart.location == cursor) {
            NSRange labelEnd = [source rangeOfString:@"](" options:0 range:searchRange];
            if (labelEnd.location != NSNotFound) {
                NSRange urlSearch = NSMakeRange(NSMaxRange(labelEnd), source.length - NSMaxRange(labelEnd));
                NSRange urlEnd = [source rangeOfString:@")" options:0 range:urlSearch];
                if (urlEnd.location != NSNotFound) {
                    NSString *label = [source substringWithRange:NSMakeRange(cursor + 1, labelEnd.location - cursor - 1)];
                    NSString *address = [source substringWithRange:NSMakeRange(NSMaxRange(labelEnd), urlEnd.location - NSMaxRange(labelEnd))];
                    NSMutableDictionary *attributes = [baseAttributes mutableCopy];
                    NSURL *url = [NSURL URLWithString:address];
                    if (url) attributes[NSLinkAttributeName] = url;
                    attributes[NSForegroundColorAttributeName] = NSColor.linkColor;
                    attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
                    [target appendAttributedString:[[NSAttributedString alloc] initWithString:label attributes:attributes]];
                    cursor = NSMaxRange(urlEnd);
                    continue;
                }
            }
        }
        [target appendAttributedString:[[NSAttributedString alloc] initWithString:[source substringWithRange:NSMakeRange(cursor, 1)] attributes:baseAttributes]];
        cursor += 1;
    }
}

static void ZhengxinAppendHelpBlock(NSMutableAttributedString *document,
                                    NSString *text,
                                    NSString *kind) {
    CGFloat size = 14;
    NSFontWeight weight = NSFontWeightRegular;
    CGFloat before = 0;
    CGFloat after = 12;
    CGFloat lineSpacing = 5;
    CGFloat firstIndent = 0;
    CGFloat headIndent = 0;
    NSString *prefix = @"";
    if ([kind isEqualToString:@"title"]) {
        size = 28; weight = NSFontWeightBold; after = 20; lineSpacing = 2;
    } else if ([kind isEqualToString:@"section"]) {
        size = 20; weight = NSFontWeightBold; before = 20; after = 10; lineSpacing = 2;
    } else if ([kind isEqualToString:@"subsection"]) {
        size = 15; weight = NSFontWeightSemibold; before = 10; after = 9; lineSpacing = 3;
    } else if ([kind isEqualToString:@"bullet"]) {
        prefix = @"•  "; firstIndent = 10; headIndent = 28; after = 8; lineSpacing = 4;
    }
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.paragraphSpacingBefore = before;
    style.paragraphSpacing = after;
    style.lineSpacing = lineSpacing;
    style.firstLineHeadIndent = firstIndent;
    style.headIndent = headIndent;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attributes = @{
        NSFontAttributeName: ZhengxinHelpFont(size, weight),
        NSForegroundColorAttributeName: NSColor.labelColor,
        NSParagraphStyleAttributeName: style
    };
    if (prefix.length) [document appendAttributedString:[[NSAttributedString alloc] initWithString:prefix attributes:attributes]];
    ZhengxinAppendInlineMarkdown(document, text, attributes);
    [document appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:attributes]];
}

static NSAttributedString *ZhengxinRenderHelpMarkdown(NSString *markdown) {
    NSMutableAttributedString *document = [[NSMutableAttributedString alloc] init];
    NSMutableArray<NSString *> *paragraphLines = [NSMutableArray array];
    NSMutableArray<NSString *> *codeLines = [NSMutableArray array];
    BOOL inCodeBlock = NO;
    void (^flushCode)(void) = ^{
        if (codeLines.count == 0) return;
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineBreakMode = NSLineBreakByCharWrapping;
        style.paragraphSpacing = 12;
        [document appendAttributedString:[[NSAttributedString alloc] initWithString:[[codeLines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] attributes:@{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: NSColor.labelColor,
            NSBackgroundColorAttributeName: NSColor.quaternaryLabelColor,
            NSParagraphStyleAttributeName: style
        }]];
        [codeLines removeAllObjects];
    };
    void (^flushParagraph)(void) = ^{
        if (paragraphLines.count == 0) return;
        ZhengxinAppendHelpBlock(document, [paragraphLines componentsJoinedByString:@" "], @"paragraph");
        [paragraphLines removeAllObjects];
    };
    for (NSString *rawLine in [markdown componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"```"]) {
            flushParagraph();
            if (inCodeBlock) flushCode();
            inCodeBlock = !inCodeBlock;
            continue;
        }
        if (inCodeBlock) {
            [codeLines addObject:rawLine];
            continue;
        }
        if (line.length == 0) {
            flushParagraph();
        } else if ([line hasPrefix:@"### "]) {
            flushParagraph();
            ZhengxinAppendHelpBlock(document, [line substringFromIndex:4], @"subsection");
        } else if ([line hasPrefix:@"## "]) {
            flushParagraph();
            ZhengxinAppendHelpBlock(document, [line substringFromIndex:3], @"section");
        } else if ([line hasPrefix:@"# "]) {
            flushParagraph();
            ZhengxinAppendHelpBlock(document, [line substringFromIndex:2], @"title");
        } else if ([line hasPrefix:@"- "]) {
            flushParagraph();
            ZhengxinAppendHelpBlock(document, [line substringFromIndex:2], @"bullet");
        } else {
            [paragraphLines addObject:line];
        }
    }
    flushParagraph();
    flushCode();
    return document;
}

@interface ZhengxinHelpDocumentView : NSView <NSTextViewDelegate>
@property NSTextView *helpTextView;
@property (copy) NSString *markdown;
@property NSMutableIndexSet *expandedSections;
- (instancetype)initWithMarkdown:(NSString *)markdown;
- (void)rebuildHelpContent;
- (void)updateDocumentGeometry;
@end

@implementation ZhengxinHelpDocumentView

- (BOOL)isFlipped { return YES; }

- (instancetype)initWithAttributedString:(NSAttributedString *)content {
    self = [super initWithFrame:NSMakeRect(0, 0, 760, 760)];
    if (!self) return nil;
    self.autoresizingMask = NSViewWidthSizable;
    self.helpTextView = [[NSTextView alloc] initWithFrame:self.bounds];
    self.helpTextView.editable = NO;
    self.helpTextView.selectable = YES;
    self.helpTextView.richText = YES;
    self.helpTextView.drawsBackground = YES;
    self.helpTextView.backgroundColor = NSColor.textBackgroundColor;
    self.helpTextView.textContainerInset = NSMakeSize(42, 36);
    self.helpTextView.verticallyResizable = YES;
    self.helpTextView.horizontallyResizable = NO;
    self.helpTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.helpTextView.textContainer.widthTracksTextView = YES;
    self.helpTextView.textContainer.heightTracksTextView = NO;
    [self.helpTextView.textStorage setAttributedString:content];
    [self addSubview:self.helpTextView];
    return self;
}

- (instancetype)initWithMarkdown:(NSString *)markdown {
    self = [self initWithAttributedString:[[NSAttributedString alloc] initWithString:@""]];
    if (!self) return nil;
    self.markdown = markdown;
    self.expandedSections = [NSMutableIndexSet indexSet];
    self.helpTextView.delegate = self;
    [self rebuildHelpContent];
    return self;
}

- (void)rebuildHelpContent {
    NSMutableAttributedString *content = [[NSMutableAttributedString alloc] init];
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"<details>\\s*<summary>(.*?)</summary>\\s*(.*?)\\s*</details>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSArray<NSTextCheckingResult *> *sections = [pattern matchesInString:self.markdown options:0 range:NSMakeRange(0, self.markdown.length)];
    NSUInteger cursor = 0;
    NSUInteger index = 0;
    for (NSTextCheckingResult *section in sections) {
        [content appendAttributedString:ZhengxinRenderHelpMarkdown([self.markdown substringWithRange:NSMakeRange(cursor, section.range.location - cursor)])];
        NSString *title = [self.markdown substringWithRange:[section rangeAtIndex:1]];
        BOOL expanded = [self.expandedSections containsIndex:index];
        NSMutableAttributedString *heading = [ZhengxinRenderHelpMarkdown([NSString stringWithFormat:@"### %@  %@", title, expanded ? @"—" : @"+"]) mutableCopy];
        // Only the heading is interactive; body links retain their original URLs.
        [heading addAttribute:NSLinkAttributeName value:[NSURL URLWithString:[NSString stringWithFormat:@"zhengxin-help://toggle/%lu", (unsigned long)index]] range:NSMakeRange(0, heading.length - 1)];
        [content appendAttributedString:heading];
        if (expanded) [content appendAttributedString:ZhengxinRenderHelpMarkdown([self.markdown substringWithRange:[section rangeAtIndex:2]])];
        cursor = NSMaxRange(section.range);
        index++;
    }
    [content appendAttributedString:ZhengxinRenderHelpMarkdown([self.markdown substringFromIndex:cursor])];
    [self.helpTextView.textStorage setAttributedString:content];
    [self updateDocumentGeometry];
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    NSURL *url = [link isKindOfClass:NSURL.class] ? link : [NSURL URLWithString:[link description]];
    if (![url.scheme isEqualToString:@"zhengxin-help"]) return NO;
    NSUInteger index = url.lastPathComponent.integerValue;
    NSClipView *clip = self.enclosingScrollView.contentView;
    NSPoint origin = clip.bounds.origin;
    if ([self.expandedSections containsIndex:index]) [self.expandedSections removeIndex:index];
    else [self.expandedSections addIndex:index];
    [self rebuildHelpContent];
    origin.y = MIN(origin.y, MAX(0, self.frame.size.height - clip.bounds.size.height));
    [clip scrollToPoint:origin];
    [self.enclosingScrollView reflectScrolledClipView:clip];
    return YES;
}

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    [self updateDocumentGeometry];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    [super resizeWithOldSuperviewSize:oldSize];
    [self updateDocumentGeometry];
}

- (void)layout {
    [super layout];
    [self updateDocumentGeometry];
}

- (void)updateDocumentGeometry {
    if (!self.superview) return;
    CGFloat viewportWidth = self.superview ? self.superview.bounds.size.width : self.bounds.size.width;
    CGFloat viewportHeight = self.superview ? self.superview.bounds.size.height : self.bounds.size.height;
    CGFloat pageWidth = MIN(844, viewportWidth);
    CGFloat x = floor((viewportWidth - pageWidth) / 2.0);
    self.helpTextView.frame = NSMakeRect(x, 0, pageWidth, MAX(viewportHeight, self.helpTextView.frame.size.height));
    self.helpTextView.textContainer.containerSize = NSMakeSize(MAX(1, pageWidth - 84), CGFLOAT_MAX);
    [self.helpTextView.layoutManager ensureLayoutForTextContainer:self.helpTextView.textContainer];
    NSRect used = [self.helpTextView.layoutManager usedRectForTextContainer:self.helpTextView.textContainer];
    CGFloat documentHeight = MAX(viewportHeight, ceil(used.size.height + 72));
    NSRect frame = self.frame;
    frame.size = NSMakeSize(viewportWidth, documentHeight);
    if (!NSEqualRects(frame, self.frame)) self.frame = frame;
    self.helpTextView.frame = NSMakeRect(x, 0, pageWidth, documentHeight);
}

@end

static NSWindow *ZhengxinCreateMarkdownHelpWindow(void) {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"正心OCR帮助" withExtension:@"md"];
    NSString *markdown = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!markdown.length) markdown = @"# 正心OCR 帮助\n\n帮助文件未能载入，请访问 https://ocr.zhengxinshushe.com 获取支持。";

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 760)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"正心OCR 帮助";
    window.contentMinSize = NSMakeSize(660, 620);
    window.releasedWhenClosed = NO;
    window.excludedFromWindowsMenu = YES;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:window.contentView.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.backgroundColor = NSColor.textBackgroundColor;
    scroll.drawsBackground = YES;

    ZhengxinHelpDocumentView *documentView = [[ZhengxinHelpDocumentView alloc] initWithMarkdown:markdown];
    documentView.frame = NSMakeRect(0, 0, scroll.contentSize.width, scroll.contentSize.height);
    scroll.documentView = documentView;
    window.contentView = scroll;
    [documentView updateDocumentGeometry];
    [window center];
    return window;
}
