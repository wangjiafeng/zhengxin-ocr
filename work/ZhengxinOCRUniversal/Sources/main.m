#import <Cocoa/Cocoa.h>
#import <sys/utsname.h>
#import "../../Shared/ZhengxinMarkdownHelp.h"
#import "../../Shared/ZhengxinPathSearch.h"

@interface VerticallyCenteredTextFieldCell : NSTextFieldCell
@end

@implementation VerticallyCenteredTextFieldCell

- (NSRect)drawingRectForBounds:(NSRect)bounds {
    NSRect rect = [super drawingRectForBounds:bounds];
    CGFloat textHeight = [self cellSizeForBounds:bounds].height;
    if (textHeight < rect.size.height) {
        rect.origin.y += floor((rect.size.height - textHeight) / 2.0);
        rect.size.height = textHeight;
    }
    return rect;
}

- (void)editWithFrame:(NSRect)frame inView:(NSView *)controlView editor:(NSText *)editor delegate:(id)delegate event:(NSEvent *)event {
    [super editWithFrame:[self drawingRectForBounds:frame] inView:controlView editor:editor delegate:delegate event:event];
}

- (void)selectWithFrame:(NSRect)frame inView:(NSView *)controlView editor:(NSText *)editor delegate:(id)delegate start:(NSInteger)start length:(NSInteger)length {
    [super selectWithFrame:[self drawingRectForBounds:frame] inView:controlView editor:editor delegate:delegate start:start length:length];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSTextField *inputField;
@property NSTextField *outputField;
@property NSTextField *environmentLabel;
@property NSTextField *statusLabel;
@property NSTextField *modeHintLabel;
@property NSPopUpButton *profilePopup;
@property NSProgressIndicator *progress;
@property NSTextView *logView;
@property NSButton *startButton;
@property NSButton *cancelButton;
@property NSString *jobID;
@property NSTimer *pollTimer;
@property NSString *lastStageMessage;
@property BOOL ancientSupported;
@property BOOL taskRunning;
@property NSWindow *helpWindow;
@end

@implementation AppDelegate

- (NSColor *)colorWithHex:(NSUInteger)hex alpha:(CGFloat)alpha {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xFF) / 255.0
                               green:((hex >> 8) & 0xFF) / 255.0
                                blue:(hex & 0xFF) / 255.0
                               alpha:alpha];
}

- (void)styleInput:(NSTextField *)field {
    field.editable = YES;
    field.selectable = YES;
    field.enabled = YES;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.textColor = [self colorWithHex:0x2A3F52 alpha:1];
    field.font = [NSFont systemFontOfSize:13];
    field.focusRingType = NSFocusRingTypeNone;
    field.accessibilityElement = YES;
    field.accessibilityRole = NSAccessibilityTextFieldRole;
}

- (NSView *)inputContainer:(NSRect)frame {
    NSView *container = [[NSView alloc] initWithFrame:frame];
    container.accessibilityElement = NO;
    container.wantsLayer = YES;
    container.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.72].CGColor;
    container.layer.cornerRadius = 10;
    container.layer.borderWidth = 1;
    container.layer.borderColor = [self colorWithHex:0xC9C9AD alpha:1].CGColor;
    return container;
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.cell = [[VerticallyCenteredTextFieldCell alloc] initTextCell:text];
    field.stringValue = text;
    field.editable = NO;
    field.selectable = YES;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    field.textColor = [self colorWithHex:(bold ? 0x2A3F52 : 0x556775) alpha:1];
    field.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return field;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    button.bezelColor = [self colorWithHex:0xCEBA7B alpha:1];
    button.contentTintColor = [self colorWithHex:0x2A3F52 alpha:1];
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    return button;
}

- (NSString *)applicationDisplayName {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"正心OCR";
}

- (NSMenuItem *)menuItem:(NSString *)title action:(SEL)action key:(NSString *)key {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key ?: @""];
    return item;
}

- (void)buildMainMenu {
    NSString *appName = self.applicationDisplayName;
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *applicationRoot = [[NSMenuItem alloc] initWithTitle:appName action:nil keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:appName];
    NSMenuItem *aboutItem = [self menuItem:[NSString stringWithFormat:@"关于%@", appName] action:@selector(showAbout:) key:@""];
    aboutItem.target = self;
    [applicationMenu addItem:aboutItem];
    [applicationMenu addItem:NSMenuItem.separatorItem];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"服务"];
    NSMenuItem *servicesItem = [self menuItem:@"服务" action:nil key:@""];
    servicesItem.submenu = servicesMenu;
    [applicationMenu addItem:servicesItem];
    [NSApp setServicesMenu:servicesMenu];
    [applicationMenu addItem:NSMenuItem.separatorItem];
    [applicationMenu addItem:[self menuItem:[NSString stringWithFormat:@"隐藏%@", appName] action:@selector(hide:) key:@"h"]];
    NSMenuItem *hideOthers = [self menuItem:@"隐藏其他" action:@selector(hideOtherApplications:) key:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [applicationMenu addItem:hideOthers];
    [applicationMenu addItem:[self menuItem:@"全部显示" action:@selector(unhideAllApplications:) key:@""]];
    [applicationMenu addItem:NSMenuItem.separatorItem];
    [applicationMenu addItem:[self menuItem:[NSString stringWithFormat:@"退出%@", appName] action:@selector(terminate:) key:@"q"]];
    applicationRoot.submenu = applicationMenu;
    [mainMenu addItem:applicationRoot];

    NSMenuItem *editRoot = [[NSMenuItem alloc] initWithTitle:@"编辑" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItem:[self menuItem:@"撤销" action:@selector(undo:) key:@"z"]];
    NSMenuItem *redo = [self menuItem:@"重做" action:@selector(redo:) key:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:redo];
    [editMenu addItem:NSMenuItem.separatorItem];
    [editMenu addItem:[self menuItem:@"剪切" action:@selector(cut:) key:@"x"]];
    [editMenu addItem:[self menuItem:@"复制" action:@selector(copy:) key:@"c"]];
    [editMenu addItem:[self menuItem:@"粘贴" action:@selector(paste:) key:@"v"]];
    [editMenu addItem:[self menuItem:@"删除" action:@selector(delete:) key:@""]];
    [editMenu addItem:[self menuItem:@"全选" action:@selector(selectAll:) key:@"a"]];
    [editMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *characters = [self menuItem:@"表情与符号" action:@selector(orderFrontCharacterPalette:) key:@" "];
    characters.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [editMenu addItem:characters];
    editRoot.submenu = editMenu;
    [mainMenu addItem:editRoot];

    NSMenuItem *windowRoot = [[NSMenuItem alloc] initWithTitle:@"窗口" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"窗口"];
    [windowMenu addItem:[self menuItem:@"最小化" action:@selector(performMiniaturize:) key:@"m"]];
    [windowMenu addItem:[self menuItem:@"缩放" action:@selector(performZoom:) key:@""]];
    [windowMenu addItem:NSMenuItem.separatorItem];
    [windowMenu addItem:[self menuItem:@"将全部窗口移到前面" action:@selector(arrangeInFront:) key:@""]];
    windowRoot.submenu = windowMenu;
    [mainMenu addItem:windowRoot];
    [NSApp setWindowsMenu:windowMenu];

    NSMenuItem *helpRoot = [[NSMenuItem alloc] initWithTitle:@"帮助" action:nil keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"帮助"];
    NSMenuItem *helpItem = [self menuItem:@"帮助" action:@selector(showHelp:) key:@""];
    helpItem.target = self;
    [helpMenu addItem:helpItem];
    [helpMenu addItem:NSMenuItem.separatorItem];
    for (NSArray<NSString *> *entry in @[
        @[@"访问官网", @"https://ocr.zhengxinshushe.com"],
        @[@"获取更新与支持", @"https://ocr.zhengxinshushe.com/download.php"],
        @[@"反馈问题", @"https://ocr.zhengxinshushe.com/download.php#feedback"]
    ]) {
        NSMenuItem *item = [self menuItem:entry[0] action:@selector(openWebLink:) key:@""];
        item.target = self;
        item.representedObject = entry[1];
        [helpMenu addItem:item];
    }
    helpRoot.submenu = helpMenu;
    [mainMenu addItem:helpRoot];
    [NSApp setHelpMenu:helpMenu];
    NSApp.mainMenu = mainMenu;
}

- (void)showAbout:(id)sender {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *releaseDate = info[@"ZhengxinReleaseDate"] ?: @"";
    NSString *edition = info[@"ZhengxinEdition"] ?: @"";
    NSString *creditsText = [NSString stringWithFormat:@"基于 PaddleOCR 编译\n%@\n发布时间：%@", edition, releaseDate];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSAttributedString *credits = [[NSAttributedString alloc] initWithString:creditsText attributes:@{
        NSParagraphStyleAttributeName: style,
        NSForegroundColorAttributeName: [self colorWithHex:0x556775 alpha:1],
        NSFontAttributeName: [NSFont systemFontOfSize:11]
    }];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionCredits: credits}];
}

- (void)showHelp:(id)sender {
    if (!self.helpWindow) self.helpWindow = ZhengxinCreateMarkdownHelpWindow();
    [self.helpWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)openWebLink:(NSMenuItem *)sender {
    NSString *address = [sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : @"";
    NSURL *url = [NSURL URLWithString:address];
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMainMenu];
    NSRect frame = NSMakeRect(0, 0, 860, 650);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"正心OCR 通用版";
    self.window.minSize = NSMakeSize(900, 650);
    self.window.backgroundColor = [self colorWithHex:0xF3F4F8 alpha:1];
    [self.window center];

    NSView *view = self.window.contentView;
    view.wantsLayer = YES;
    view.layer.backgroundColor = [self colorWithHex:0xF3F4F8 alpha:1].CGColor;
    [view addSubview:[self label:@"文献识别" frame:NSMakeRect(28, 600, 600, 34) size:26 bold:YES]];
    [view addSubview:[self label:@"首次运行自动检测芯片，并安装对应的 PaddleOCR 环境与模型" frame:NSMakeRect(30, 572, 760, 24) size:13 bold:NO]];

    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *machine = [NSString stringWithUTF8String:systemInfo.machine];
    self.ancientSupported = [machine isEqualToString:@"arm64"];

    self.environmentLabel = [self label:@"正在检查处理器、运行环境和模型…" frame:NSMakeRect(30, 530, 790, 25) size:13 bold:NO];
    [view addSubview:self.environmentLabel];
    [view addSubview:[self button:@"安装运行环境" action:@selector(setupRuntime:) frame:NSMakeRect(30, 490, 140, 32)]];
    [view addSubview:[self button:@"安装/更新模型" action:@selector(setupModels:) frame:NSMakeRect(180, 490, 145, 32)]];
    [view addSubview:[self button:@"重新检查" action:@selector(refreshEnvironment:) frame:NSMakeRect(335, 490, 100, 32)]];

    [view addSubview:[self label:@"输入文件" frame:NSMakeRect(30, 443, 90, 30) size:13 bold:YES]];
    NSView *inputContainer = [self inputContainer:NSMakeRect(120, 443, 700, 30)];
    self.inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 4, 650, 22)];
    [self styleInput:self.inputField];
    self.inputField.placeholderString = @"PDF、PNG、JPEG 或 TIFF";
    self.inputField.identifier = @"inputFileField";
    self.inputField.accessibilityLabel = @"输入文件路径";
    [inputContainer addSubview:self.inputField];
    [view addSubview:inputContainer];
    NSButton *chooseInputButton = ZhengxinPathSearchButton(self, @selector(chooseInput:), @"选择PDF或图像");
    [inputContainer addSubview:chooseInputButton];

    [view addSubview:[self label:@"输出目录" frame:NSMakeRect(30, 403, 90, 30) size:13 bold:YES]];
    NSView *outputContainer = [self inputContainer:NSMakeRect(120, 403, 700, 30)];
    self.outputField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 4, 650, 22)];
    [self styleInput:self.outputField];
    self.outputField.placeholderString = @"识别结果保存位置";
    self.outputField.identifier = @"outputDirectoryField";
    self.outputField.accessibilityLabel = @"输出目录路径";
    [outputContainer addSubview:self.outputField];
    [view addSubview:outputContainer];
    NSButton *chooseOutputButton = ZhengxinPathSearchButton(self, @selector(chooseOutput:), @"选择输出目录");
    [outputContainer addSubview:chooseOutputButton];

    [view addSubview:[self label:@"识别模式" frame:NSMakeRect(30, 359, 90, 30) size:13 bold:YES]];
    self.profilePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(120, 359, 250, 30) pullsDown:NO];
    self.profilePopup.bezelColor = [self colorWithHex:0xCEBA7B alpha:0.48];
    self.profilePopup.contentTintColor = [self colorWithHex:0x2A3F52 alpha:1];
    if (self.ancientSupported) {
        [self.profilePopup addItemsWithTitles:@[@"古籍正本（PaddleOCR-VL）", @"复杂排版（PP-StructureV3）", @"普通扫描（PP-OCRv6）"]];
    } else {
        [self.profilePopup addItemsWithTitles:@[@"复杂排版（PP-Structure 2.x）", @"普通扫描（PP-OCR 2.x）"]];
    }
    self.profilePopup.target = self;
    self.profilePopup.action = @selector(profileChanged:);
    [view addSubview:self.profilePopup];
    NSString *modeHint = self.ancientSupported ? @"古籍模式适合竖排、夹注、生僻字；16GB 内存时按页单并发运行。" : @"复杂排版适合多栏、表格、公式、图片与正文混排。";
    self.modeHintLabel = [self label:modeHint frame:NSMakeRect(385, 359, 435, 30) size:12 bold:NO];
    [view addSubview:self.modeHintLabel];

    self.startButton = [self button:@"开始识别" action:@selector(startOCR:) frame:NSMakeRect(30, 310, 120, 36)];
    self.startButton.keyEquivalent = @"\r";
    [view addSubview:self.startButton];
    self.cancelButton = [self button:@"取消任务" action:@selector(cancelOCR:) frame:NSMakeRect(160, 310, 110, 36)];
    self.cancelButton.enabled = NO;
    [view addSubview:self.cancelButton];
    [view addSubview:[self button:@"显示结果" action:@selector(revealOutput:) frame:NSMakeRect(280, 310, 110, 36)]];

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(410, 318, 410, 18)];
    self.progress.indeterminate = NO;
    self.progress.minValue = 0;
    self.progress.maxValue = 1;
    [view addSubview:self.progress];
    self.statusLabel = [self label:@"尚未提交任务" frame:NSMakeRect(30, 275, 790, 24) size:13 bold:NO];
    [view addSubview:self.statusLabel];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(30, 24, 790, 240)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.wantsLayer = YES;
    scroll.layer.cornerRadius = 0;
    scroll.layer.masksToBounds = YES;
    scroll.layer.borderWidth = 1;
    scroll.layer.borderColor = [self colorWithHex:0xC9C9AD alpha:1].CGColor;
    scroll.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.72].CGColor;
    self.logView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    self.logView.editable = NO;
    self.logView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.logView.textColor = [self colorWithHex:0x2A3F52 alpha:1];
    self.logView.backgroundColor = [NSColor colorWithWhite:1 alpha:0.42];
    scroll.documentView = self.logView;
    [view addSubview:scroll];

    for (NSView *child in view.subviews) child.autoresizingMask = NSViewMinYMargin;
    self.environmentLabel.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    inputContainer.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    outputContainer.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    self.inputField.autoresizingMask = NSViewWidthSizable;
    self.outputField.autoresizingMask = NSViewWidthSizable;
    self.inputField.nextKeyView = self.outputField;
    self.outputField.nextKeyView = self.profilePopup;
    self.modeHintLabel.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    chooseInputButton.autoresizingMask = NSViewMinXMargin;
    chooseOutputButton.autoresizingMask = NSViewMinXMargin;
    self.progress.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    self.statusLabel.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.inputField];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshEnvironment:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (!self.taskRunning || self.jobID.length == 0) return NSTerminateNow;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"当前识别任务尚未完成";
    alert.informativeText = @"您可以让任务继续在本机运行，或取消任务后退出程序。";
    [alert addButtonWithTitle:@"继续识别并退出"];
    [alert addButtonWithTitle:@"取消任务并退出"];
    [alert addButtonWithTitle:@"返回"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) return NSTerminateNow;
    if (response == NSAlertSecondButtonReturn) {
        [self runArguments:@[@"cancel", self.jobID, @"--json"] completion:^(int code, NSString *output) {
            self.taskRunning = NO;
            [self.pollTimer invalidate];
            self.pollTimer = nil;
            [NSApp replyToApplicationShouldTerminate:YES];
        }];
        return NSTerminateLater;
    }
    return NSTerminateCancel;
}

- (NSString *)cliPath {
    return [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"bin/localocr"].path;
}

- (void)appendLog:(NSString *)text {
    if (text.length == 0) return;
    NSString *current = self.logView.string ?: @"";
    NSString *combined = current.length ? [current stringByAppendingFormat:@"\n%@", text] : text;
    if (combined.length > 30000) combined = [combined substringFromIndex:combined.length - 30000];
    self.logView.string = combined;
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
}

- (void)runArguments:(NSArray<NSString *> *)arguments completion:(void (^)(int, NSString *))completion {
    BOOL streamOutput = [arguments.firstObject hasPrefix:@"setup-"];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:self.cliPath];
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        completion(127, error.localizedDescription ?: @"无法启动本地 OCR 工具");
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableData *collected = [NSMutableData data];
        while (YES) {
            NSData *chunk = [pipe.fileHandleForReading readDataOfLength:4096];
            if (chunk.length == 0) break;
            [collected appendData:chunk];
            NSString *text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
            if (streamOutput && text.length) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self appendLog:text]; });
            }
        }
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:collected encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(task.terminationStatus, output); });
    });
}

- (void)setControlsBusy:(BOOL)busy message:(NSString *)message {
    self.startButton.enabled = !busy;
    if (message) self.statusLabel.stringValue = message;
}

- (void)refreshEnvironment:(id)sender {
    [self runArguments:@[@"doctor", @"--json"] completion:^(int code, NSString *output) {
        [self appendLog:output];
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        BOOL runtime = [json[@"runtime_ready"] boolValue];
        BOOL models = [json[@"models_ready"] boolValue];
        NSString *python = json[@"python"];
        if (!python.length) {
            NSString *systemVersion = json[@"system_python_version"];
            python = systemVersion.length ? [NSString stringWithFormat:@"%@（本机）", systemVersion] : @"未检测到兼容版本";
        }
        NSString *arch = json[@"architecture"] ?: @"未知";
        self.environmentLabel.stringValue = [NSString stringWithFormat:@"架构：%@　Python：%@　运行环境：%@　模型：%@", arch, python, runtime ? @"已就绪" : @"未安装", models ? @"已就绪" : @"未安装"];
        self.startButton.enabled = runtime && models;
    }];
}

- (void)setupRuntime:(id)sender {
    self.progress.indeterminate = YES;
    [self.progress startAnimation:nil];
        [self setControlsBusy:YES message:@"正在检测本机 Python 并安装 OCR 依赖，请保持联网…"];
    [self runArguments:@[@"setup-runtime"] completion:^(int code, NSString *output) {
        [self.progress stopAnimation:nil];
        self.progress.indeterminate = NO;
        self.progress.doubleValue = 0;
        [self setControlsBusy:NO message:code == 0 ? @"运行环境安装完成，请继续安装模型" : @"运行环境安装失败，请查看日志"];
        [self refreshEnvironment:nil];
    }];
}

- (void)setupModels:(id)sender {
    self.progress.indeterminate = YES;
    [self.progress startAnimation:nil];
    [self setControlsBusy:YES message:@"正在下载并初始化模型，请保持联网…"];
    [self runArguments:@[@"setup-models"] completion:^(int code, NSString *output) {
        [self.progress stopAnimation:nil];
        self.progress.indeterminate = NO;
        self.progress.doubleValue = 0;
        [self setControlsBusy:NO message:code == 0 ? @"模型安装完成，可以断网识别" : @"模型安装失败，请查看日志"];
        [self refreshEnvironment:nil];
    }];
}

- (void)chooseInput:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"选择 PDF 或图像";
    panel.allowedFileTypes = @[@"pdf", @"png", @"jpg", @"jpeg", @"tif", @"tiff"];
    if ([panel runModal] == NSModalResponseOK) {
        self.inputField.stringValue = panel.URL.path;
        if (self.outputField.stringValue.length == 0) {
            NSURL *parent = [panel.URL URLByDeletingLastPathComponent];
            NSString *name = panel.URL.URLByDeletingPathExtension.lastPathComponent;
            self.outputField.stringValue = [[parent URLByAppendingPathComponent:[name stringByAppendingString:@"-OCR结果"]] path];
        }
    }
}

- (void)chooseOutput:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"选择结果保存目录";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    if ([panel runModal] == NSModalResponseOK) self.outputField.stringValue = panel.URL.path;
}

- (NSString *)selectedProfile {
    if (!self.ancientSupported) return self.profilePopup.indexOfSelectedItem == 0 ? @"complex" : @"modern";
    if (self.profilePopup.indexOfSelectedItem == 1) return @"complex";
    if (self.profilePopup.indexOfSelectedItem == 2) return @"modern";
    return @"ancient";
}

- (void)profileChanged:(id)sender {
    NSString *profile = self.selectedProfile;
    if ([profile isEqualToString:@"complex"]) {
        self.modeHintLabel.stringValue = @"复杂排版适合多栏、表格、公式、图片与正文混排。";
    } else if ([profile isEqualToString:@"modern"]) {
        self.modeHintLabel.stringValue = @"普通扫描适合现代横排印刷体和规整扫描件，速度最快。";
    } else {
        self.modeHintLabel.stringValue = @"古籍模式适合竖排、夹注、生僻字；16GB 内存时按页单并发运行。";
    }
}

- (void)startOCR:(id)sender {
    if (self.inputField.stringValue.length == 0 || self.outputField.stringValue.length == 0) {
        self.statusLabel.stringValue = @"请先选择输入文件和输出目录";
        return;
    }
    [self setControlsBusy:YES message:@"正在提交本地识别任务…"];
    NSArray *args = @[@"submit", self.inputField.stringValue, @"--profile", self.selectedProfile, @"--output", self.outputField.stringValue, @"--start", @"--json"];
    [self runArguments:args completion:^(int code, NSString *output) {
        [self appendLog:output];
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        self.jobID = json[@"job_id"];
        if (code == 0 && self.jobID.length) {
            self.taskRunning = YES;
            self.statusLabel.stringValue = [NSString stringWithFormat:@"任务已提交：%@", self.jobID];
            self.cancelButton.enabled = YES;
            self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(pollStatus:) userInfo:nil repeats:YES];
            [self pollStatus:nil];
        } else {
            [self setControlsBusy:NO message:@"提交失败，请查看日志"];
        }
    }];
}

- (void)pollStatus:(id)sender {
    if (self.jobID.length == 0) return;
    [self runArguments:@[@"status", self.jobID, @"--json"] completion:^(int code, NSString *output) {
        NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *status = json[@"status"] ?: @"unknown";
        NSInteger processed = [json[@"processed_pages"] integerValue];
        if (!json[@"processed_pages"]) processed = [json[@"completed_pages"] integerValue];
        NSInteger rendered = [json[@"rendered_pages"] integerValue];
        NSInteger recognized = [json[@"recognized_pages"] integerValue];
        if (!json[@"recognized_pages"]) recognized = [json[@"completed_pages"] integerValue];
        NSInteger current = [json[@"current_page"] integerValue];
        NSInteger total = [json[@"total_pages"] integerValue];
        NSInteger failed = [json[@"failed_pages"] integerValue];
        NSString *message = json[@"stage_message"] ?: status;
        NSInteger progressPages = MAX(processed, rendered);
        self.progress.doubleValue = total > 0 ? (double)progressPages / (double)total : 0;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@　当前：%ld/%ld　已渲染：%ld　已识别：%ld　失败：%ld", message, (long)current, (long)total, (long)rendered, (long)recognized, (long)failed];
        if (message.length && ![message isEqualToString:self.lastStageMessage]) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"HH:mm:ss";
            [self appendLog:[NSString stringWithFormat:@"[%@] %@", [formatter stringFromDate:[NSDate date]], message]];
            self.lastStageMessage = message;
        }
        NSSet *terminal = [NSSet setWithArray:@[@"completed", @"completed_with_errors", @"failed", @"cancelled"]];
        if ([terminal containsObject:status]) {
            self.taskRunning = NO;
            [self.pollTimer invalidate];
            self.pollTimer = nil;
            self.startButton.enabled = YES;
            self.cancelButton.enabled = NO;
        }
    }];
}

- (void)cancelOCR:(id)sender {
    if (self.jobID.length == 0) return;
    [self runArguments:@[@"cancel", self.jobID, @"--json"] completion:^(int code, NSString *output) {
        [self appendLog:output];
        [self pollStatus:nil];
    }];
}

- (void)revealOutput:(id)sender {
    if (self.outputField.stringValue.length) {
        [[NSWorkspace sharedWorkspace] selectFile:nil inFileViewerRootedAtPath:self.outputField.stringValue];
    }
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
