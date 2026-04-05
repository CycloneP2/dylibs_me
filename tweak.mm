// tweak.mm - MLBB Pro Mod (Draggable, Show/Hide, Persistent Settings)
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
// ============================================
// OFFSETS (Pastikan offset ini benar untuk MLBB kamu)
// ============================================
#define OFF_TUTORIAL_PATCH          0x939cc
#define OFF_RADAR_X                 0x92c94
#define OFF_RADAR_Y                 0x92ca3
#define OFF_RADAR_SIZE              0x92cb2
#define OFF_BAN_BYPASS              0x961b8
static uintptr_t unityBase = 0;
// Feature states (Loaded/Saved via NSUserDefaults)
static BOOL tutorialEnabled = NO;
static BOOL radarEnabled = NO;
static BOOL banBypassEnabled = NO;
// ============================================
// MEMORY HELPERS
// ============================================
uintptr_t get_base_address(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *img_name = _dyld_get_image_name(i);
        if (img_name && strstr(img_name, name)) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}
void writeInt(uintptr_t address, int value) {
    if (!address) return;
    vm_protect(mach_task_self(), (vm_address_t)address, sizeof(int), 0, VM_PROT_READ | VM_PROT_WRITE);
    *(int *)address = value;
}
void patchMemory(uintptr_t address, unsigned char bytes[], size_t len) {
    if (!address) return;
    vm_protect(mach_task_self(), (vm_address_t)address, len, 0, VM_PROT_READ | VM_PROT_WRITE);
    memcpy((void *)address, bytes, len);
}
// ============================================
// MOD LOGIC (Skip Tutorial & Radar)
// ============================================
void applyTutorial(BOOL enable) {
    if (!unityBase) return;
    uintptr_t addr = unityBase + OFF_TUTORIAL_PATCH;
    if (enable) {
        unsigned char patch[] = {0x20, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6}; // mov x0,#1; ret
        patchMemory(addr, patch, 8);
    } else {
        unsigned char orig[] = {0x00, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6}; // mov x0,#0; ret
        patchMemory(addr, orig, 8);
    }
}
void applyRadar(BOOL enable) {
    if (!unityBase) return;
    writeInt(unityBase + OFF_RADAR_X, enable ? 9999 : 0);
    writeInt(unityBase + OFF_RADAR_Y, enable ? 9999 : 0);
    writeInt(unityBase + OFF_RADAR_SIZE, enable ? 200 : 100);
}
void applyBanBypass(BOOL enable) {
    if (!unityBase) return;
    uintptr_t addr = unityBase + OFF_BAN_BYPASS;
    unsigned char patch = enable ? 0x01 : 0x00;
    patchMemory(addr, &patch, 1);
}
// ============================================
// UI COMPONENTS
// ============================================
@interface ModMenu : UIView
@property (nonatomic, assign) CGPoint startLocation;
- (void)setupFeatures;
@end
@implementation ModMenu
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.frame = self.bounds;
        blurView.layer.cornerRadius = 20;
        blurView.layer.masksToBounds = YES;
        blurView.layer.borderWidth = 1.5;
        blurView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:0.8].CGColor;
        [self addSubview:blurView];
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, frame.size.width, 30)];
        title.text = @"🛸 MLBB GALAXY MOD";
        title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:18];
        [self addSubview:title];
        [self setupFeatures];
    }
    return self;
}
- (void)setupFeatures {
    NSArray *titles = @[@"Skip Tutorial", @"Map Radar Hack", @"Anti-Ban Bypass"];
    NSArray *states = @[@(tutorialEnabled), @(radarEnabled), @(banBypassEnabled)];
    for (int i = 0; i < titles.count; i++) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 50 + (i * 50), 180, 30)];
        label.text = titles[i];
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:14];
        [self addSubview:label];
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(210, 50 + (i * 50), 50, 30)];
        sw.on = [states[i] boolValue];
        sw.tag = i;
        sw.onTintColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
        [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:sw];
    }
}
- (void)toggleChanged:(UISwitch *)sender {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    switch (sender.tag) {
        case 0:
            tutorialEnabled = sender.on;
            applyTutorial(tutorialEnabled);
            [defs setBool:tutorialEnabled forKey:@"ML_Tutorial"];
            break;
        case 1:
            radarEnabled = sender.on;
            applyRadar(radarEnabled);
            [defs setBool:radarEnabled forKey:@"ML_Radar"];
            break;
        case 2:
            banBypassEnabled = sender.on;
            applyBanBypass(banBypassEnabled);
            [defs setBool:banBypassEnabled forKey:@"ML_Ban"];
            break;
    }
    [defs synchronize];
}
// Draggable Logic
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.startLocation = [[touches anyObject] locationInView:self];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInView:self.superview];
    self.center = CGPointMake(loc.x - self.startLocation.x + self.bounds.size.width/2,
                              loc.y - self.startLocation.y + self.bounds.size.height/2);
}
@end
// ============================================
// SINGLETON MANAGER
// ============================================
@interface ModManager : NSObject
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) ModMenu *mainMenu;
@property (nonatomic, assign) CGPoint startLocation;
+ (instancetype)shared;
- (void)initInterface;
@end
@implementation ModManager
+ (instancetype)shared {
    static ModManager *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[self alloc] init]; });
    return inst;
}
- (void)initInterface {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        if (!win) return;
        // LOAD SAVED SETTINGS
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        tutorialEnabled = [defs boolForKey:@"ML_Tutorial"];
        radarEnabled = [defs boolForKey:@"ML_Radar"];
        banBypassEnabled = [defs boolForKey:@"ML_Ban"];
        // APPLY INITIAL SETTINGS
        applyTutorial(tutorialEnabled);
        applyRadar(radarEnabled);
        applyBanBypass(banBypassEnabled);
        // CREATE FLOATING BUTTON
        self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatBtn.frame = CGRectMake(20, 100, 55, 55);
        self.floatBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
        self.floatBtn.layer.cornerRadius = 27.5;
        self.floatBtn.layer.borderWidth = 2;
        self.floatBtn.layer.borderColor = [UIColor whiteColor].CGColor;
        [self.floatBtn setTitle:@"🔧" forState:UIControlStateNormal];
        self.floatBtn.titleLabel.font = [UIFont systemFontOfSize:25];
        [self.floatBtn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];
        
        // Draggable Button Logic
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(hdlPan:)];
        [self.floatBtn addGestureRecognizer:pan];
        [win addSubview:self.floatBtn];
        // CREATE MENU
        self.mainMenu = [[ModMenu alloc] initWithFrame:CGRectMake(50, 180, 280, 250)];
        self.mainMenu.hidden = YES;
        [win addSubview:self.mainMenu];
    });
}
- (void)btnTapped {
    self.mainMenu.hidden = !self.mainMenu.isHidden;
}
- (void)hdlPan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint trans = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + trans.x, v.center.y + trans.y);
    [p setTranslation:CGPointZero inView:v.superview];
}
@end
// ============================================
// CONSTRUCTOR
// ============================================
__attribute__((constructor))
void init() {
    // 1. Force Load Library
    dlopen("/private/var/containers/Bundle/Application/*/mlbb.app/Frameworks/UnityFramework.framework/UnityFramework", RTLD_LAZY);
    
    // 2. Cari Base Address (Penting!)
    unityBase = get_base_address("UnityFramework");
    if (!unityBase) {
        NSLog(@"[MLBB Mod] WARNING: UnityFramework NOT FOUND!");
        return;
    }
    
    // 3. Init Mod Menu Interface
    [[ModManager shared] initInterface];
    
    NSLog(@"[MLBB Mod] Menu Loaded on Frame: %p", (void *)unityBase);
}
