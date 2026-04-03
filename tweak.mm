
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <fishhook.h>

// ============================================
// GLOBAL TOGGLES
// ============================================
static BOOL mapHackEnabled = YES;

// ============================================
// UTILITY FUNCTIONS
// ============================================
static uintptr_t getBaseAddress() {
    return (uintptr_t)_dyld_get_image_header(0);
}

static void* getFunction(uintptr_t offset) {
    return (void*)(getBaseAddress() + offset);
}

// ============================================
// MAP HACK OFFSETS (dari dump.cs)
// ============================================
// ShowFogMgr.SetIsShowFog - offset 0x58533C0
#define OFFSET_ShowFogMgr_SetIsShowFog 0x58533C0
#define OFFSET_ShowFogMgr_GetInstance 0x5853370

// ============================================
// MAP HACK OFFSETS (dari dump.cs)
// ============================================
// ShowFogMgr.SetIsShowFog - offset 0x58533C0
define OFFSET_ShowFogMgr_SetIsShowFog 0x58533C0
define OFFSET_ShowFogMgr_GetInstance 0x5853370


// ============================================
// DNS BYPASS - BLOCK ANTI CHEAT (biar aman)
// ============================================
static int (*orig_getaddrinfo)(const char*, const char*, const struct addrinfo*, struct addrinfo**);

static int hooked_getaddrinfo(const char* node, const char* service, const struct addrinfo* hints, struct addrinfo** res) {
    if (node) {
        NSString *host = [NSString stringWithUTF8String:node];
        NSArray *blocked = @[@"moonton", @"anticheat", @"report", @"mlbb", @"api", @"youngjoygame"];
        for (NSString *pattern in blocked) {
            if ([host containsString:pattern]) {
                return EAI_NONAME;
            }
        }
    }
    return orig_getaddrinfo(node, service, hints, res);
}

// ============================================
// MAP HACK HOOK - FORCE FOG = FALSE
// ============================================
static void (*orig_SetIsShowFog)(void* fogMgr, BOOL showFog);

static void hooked_SetIsShowFog(void* fogMgr, BOOL showFog) {
    if (mapHackEnabled) {
        // Force fog of war = NO (lihat seluruh map)
        orig_SetIsShowFog(fogMgr, NO);
    } else {
        orig_SetIsShowFog(fogMgr, showFog);
    }
}

// ============================================
// SETUP HOOKS
// ============================================
static void setupHooks() {
    uintptr_t base = getBaseAddress();
    
    // DNS Hook via fishhook
    struct rebinding dns_rebind = {"getaddrinfo", (void*)hooked_getaddrinfo, (void**)&orig_getaddrinfo};
    rebind_symbols(&dns_rebind, 1);
    NSLog(@"[DNS] Bypass Enabled");
    
    // Map Hack Hook
    void* setFogAddr = (void*)(base + OFFSET_ShowFogMgr_SetIsShowFog);
    if (setFogAddr) {
        MSHookFunction(setFogAddr, (void*)&hooked_SetIsShowFog, (void**)&orig_SetIsShowFog);
        NSLog(@"[Map Hack] Hook applied at 0x%lx", (unsigned long)OFFSET_ShowFogMgr_SetIsShowFog);
    } else {
        NSLog(@"[Map Hack] Failed to find SetIsShowFog function");
    }
    
    // Wipe memory flags biar ga kena ban
    void* reportFlagAddr = (void*)(base + 0x189FF);
    memset(reportFlagAddr, 0, 1);
    void* scannerAddr = (void*)(base + 0x18A36);
    *(int*)scannerAddr = 0x7FFFFFFF;
    
    NSLog(@"[MLBB] Map Hack + DNS Bypass Active");
}

// ============================================
// COMPACT DRAGGABLE MENU BUTTON (iOSGods Style)
// ============================================
@interface MiniMenuButton : UIButton {
    UIView *fullMenuView;
    BOOL isMenuVisible;
}
@end

@implementation MiniMenuButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.85];
        self.layer.cornerRadius = 25;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor cyanColor].CGColor;
        [self setTitle:@"ML" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
        [self addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        
        isMenuVisible = NO;
        [self createSimpleMenu];
    }
    return self;
}

- (void)drag:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    CGFloat halfWidth = self.bounds.size.width / 2;
    CGFloat halfHeight = self.bounds.size.height / 2;
    newCenter.x = MAX(halfWidth, MIN(newCenter.x, self.superview.bounds.size.width - halfWidth));
    newCenter.y = MAX(halfHeight + 20, MIN(newCenter.y, self.superview.bounds.size.height - halfHeight - 20));
    self.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.superview];
    if (fullMenuView && !fullMenuView.hidden) {
        fullMenuView.center = newCenter;
    }
}

- (void)createSimpleMenu {
    fullMenuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 160)];
    fullMenuView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
    fullMenuView.layer.cornerRadius = 15;
    fullMenuView.layer.borderWidth = 1;
    fullMenuView.layer.borderColor = [UIColor cyanColor].CGColor;
    fullMenuView.hidden = YES;
    
    // Title Bar
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 35)];
    titleBar.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    [fullMenuView addSubview:titleBar];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 180, 25)];
    titleLabel.text = @"MLBB MAP HACK";
    titleLabel.textColor = [UIColor yellowColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [titleBar addSubview:titleLabel];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(200, 5, 30, 25);
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:closeBtn];
    
    // Map Hack Toggle
    UISwitch *mapSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(15, 55, 0, 0)];
    mapSwitch.on = mapHackEnabled;
    [mapSwitch addTarget:self action:@selector(toggleMapHack:) forControlEvents:UIControlEventValueChanged];
    [fullMenuView addSubview:mapSwitch];
    
    UILabel *mapLabel = [[UILabel alloc] initWithFrame:CGRectMake(75, 55, 150, 30)];
    mapLabel.text = @"MAP HACK (No Fog)";
    mapLabel.textColor = [UIColor whiteColor];
    mapLabel.font = [UIFont boldSystemFontOfSize:14];
    [fullMenuView addSubview:mapLabel];
    
    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 100, 210, 40)];
    statusLabel.text = @"Status: ACTIVE\nSee whole map, no fog";
    statusLabel.textColor = [UIColor greenColor];
    statusLabel.font = [UIFont systemFontOfSize:10];
    statusLabel.numberOfLines = 2;
    [fullMenuView addSubview:statusLabel];
    
    [self.superview addSubview:fullMenuView];
}

- (void)toggleMapHack:(UISwitch*)sender {
    mapHackEnabled = sender.isOn;
    NSLog(@"[Map Hack] %@", mapHackEnabled ? @"ENABLED" : @"DISABLED");
}

- (void)toggleMenu {
    isMenuVisible = !isMenuVisible;
    fullMenuView.hidden = !isMenuVisible;
    if (isMenuVisible) {
        fullMenuView.center = self.center;
    }
}

- (void)hideMenu {
    isMenuVisible = NO;
    fullMenuView.hidden = YES;
}

@end

// ============================================
// CONSTRUCTOR - ENTRY POINT
// ============================================
__attribute__((constructor))
static void initialize() {
    setupHooks();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) {
            NSArray *windows = [UIApplication sharedApplication].windows;
            if (windows.count > 0) {
                keyWindow = windows.firstObject;
            }
        }
        if (!keyWindow) return;
        
        // Add draggable menu button
        MiniMenuButton *menuBtn = [[MiniMenuButton alloc] initWithFrame:CGRectMake(15, 120, 50, 50)];
        [keyWindow addSubview:menuBtn];
        
        NSLog(@"[MLBB] Map Hack dylib loaded - all fog removed");
    });
}
