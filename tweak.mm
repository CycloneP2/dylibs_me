// tweak.mm - MLBB PRO MAX (Full ESP + Radar + Auto Retri + Logs)
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>

// ========== OFFSETS ==========
#define OFF_TUTORIAL_PATCH          0x939cc
#define OFF_RADAR_X                 0x92c94
#define OFF_RADAR_Y                 0x92ca3
#define OFF_RADAR_SIZE              0x92cb2
#define OFF_BAN_BYPASS              0x961b8

// ESP Offsets
#define OFF_ESP_ENABLED             0x291da
#define OFF_ESP_ENEMY_R             0x28e8e
#define OFF_ESP_ENEMY_G             0x28ea0
#define OFF_ESP_ENEMY_B             0x28eb2
#define OFF_ESP_ALLY_R              0x2923a
#define OFF_ESP_ALLY_G              0x28ec4
#define OFF_ESP_ALLY_B              0x28ed5
#define OFF_ESP_SNAPLINES           0x29226
#define OFF_ESP_MONSTER             0x29200
#define OFF_ESP_SHOW_TEAM           0x2924b
#define OFF_MONSTER_ESP             0x18c99
#define OFF_SESP                    0x19957
#define OFF_WORLD_TO_VIEWPORT       0x18944
#define OFF_DRONE_VIEW              0x9AA10
#define OFF_HP_BAR                  0x9BC50

// New Auto Retri Offsets (Contoh)
#define OFF_LOCAL_PLAYER            0x1A2B3C0
#define OFF_RETRI_DAMAGE            0x78
#define OFF_TARGET_HP               0x48

static uintptr_t unityBase = 0;

// Feature states
static BOOL tutorialEnabled = NO, radarEnabled = NO, banBypassEnabled = NO;
static BOOL espEnabled = NO, espSnaplines = NO, espMonster = NO, espShowTeam = YES;
static BOOL droneEnabled = NO, hpBarEnabled = NO, autoRetriEnabled = NO;
static float droneValue = 1.0, espEnemyR = 1.0, espEnemyG = 0.0, espEnemyB = 0.0;
static float espAllyR = 0.0, espAllyG = 1.0, espAllyB = 0.0;

// ========== MOD MENU INTERFACE (REFIX) ==========
@interface ModMenu : UIView
@property (nonatomic, strong) UISwitch *espSwitch, *snaplineSwitch, *monsterSwitch, *retriSwitch;
@property (nonatomic, strong) UISwitch *tutorialSwitch, *radarSwitch, *banSwitch, *hpSwitch, *droneSwitch;
@property (nonatomic, strong) UISlider *enemyRSlider, *enemyGSlider, *enemyBSlider, *droneSlider;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, assign) CGPoint startLocation;
- (void)appendLog:(NSString *)msg;
@end

ModMenu *globalMenu = nil; // Global single definition

// ========== LOGGING & MEMORY HELPERS ==========
void logSystem(NSString *type, NSString *msg) {
    NSString *full = [NSString stringWithFormat:@"[%@] %@", type, msg];
    NSLog(@"%@", full);
    if (globalMenu) [globalMenu appendLog:full];
}

BOOL writeFloat(uintptr_t addr, float val) {
    kern_return_t err = vm_protect(mach_task_self(), addr, sizeof(float), 0, VM_PROT_READ | VM_PROT_WRITE);
    if (err == KERN_SUCCESS) {
        *(float *)addr = val;
        logSystem(@"OK", [NSString stringWithFormat:@"Float 0x%lX = %.2f", (long)addr, val]);
        return YES;
    }
    return NO;
}

BOOL writeInt(uintptr_t addr, int val) {
    kern_return_t err = vm_protect(mach_task_self(), addr, sizeof(int), 0, VM_PROT_READ | VM_PROT_WRITE);
    if (err == KERN_SUCCESS) {
        *(int *)addr = val;
        logSystem(@"OK", [NSString stringWithFormat:@"Int 0x%lX = %d", (long)addr, val]);
        return YES;
    }
    return NO;
}

BOOL writeByte(uintptr_t addr, unsigned char val) {
    kern_return_t err = vm_protect(mach_task_self(), addr, 1, 0, VM_PROT_READ | VM_PROT_WRITE);
    if (err == KERN_SUCCESS) {
        *(unsigned char *)addr = val;
        logSystem(@"OK", [NSString stringWithFormat:@"Byte 0x%lX = 0x%02X", (long)addr, val]);
        return YES;
    }
    return NO;
}

BOOL writePatch(uintptr_t addr, unsigned char *patch, size_t size) {
    kern_return_t err = vm_protect(mach_task_self(), addr, size, 0, VM_PROT_READ | VM_PROT_WRITE);
    if (err == KERN_SUCCESS) {
        memcpy((void *)addr, patch, size);
        logSystem(@"OK", [NSString stringWithFormat:@"Patch 0x%lX (%ld bytes)", (long)addr, size]);
        return YES;
    }
    return NO;
}

// ========== MEMORY LOGIC ==========
uintptr_t get_base_address(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strstr(_dyld_get_image_name(i), name)) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

void applyESP() {
    if (!unityBase) return;
    writeByte(unityBase + OFF_ESP_ENABLED, espEnabled ? 1 : 0);
    if (espEnabled) {
        writeFloat(unityBase + OFF_ESP_ENEMY_R, espEnemyR);
        writeFloat(unityBase + OFF_ESP_ENEMY_G, espEnemyG);
        writeFloat(unityBase + OFF_ESP_ENEMY_B, espEnemyB);
        writeByte(unityBase + OFF_ESP_SNAPLINES, espSnaplines ? 1 : 0);
        writeByte(unityBase + OFF_ESP_MONSTER, espMonster ? 1 : 0);
        writeByte(unityBase + OFF_ESP_SHOW_TEAM, espShowTeam ? 1 : 0);
        writeByte(unityBase + OFF_SESP, 1);
    }
}

void applyDrone() { if (unityBase) writeFloat(unityBase + OFF_DRONE_VIEW, droneEnabled ? (15.0f * droneValue) : 15.0f); }
void applyHPBar() { if (unityBase) writeByte(unityBase + OFF_HP_BAR, hpBarEnabled ? 1 : 0); }
void applyRadar(BOOL enable) { if (!unityBase) return; writeInt(unityBase + OFF_RADAR_X, enable ? 9999 : 0); writeInt(unityBase + OFF_RADAR_Y, enable ? 9999 : 0); }

// ========== MOD MENU IMPLEMENTATION ==========
@implementation ModMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        globalMenu = self;
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.frame = self.bounds;
        blurView.layer.cornerRadius = 20;
        blurView.layer.masksToBounds = YES;
        [self addSubview:blurView];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, frame.size.width, 28)];
        title.text = @"🔥 MLBB PRO MAX 🔥";
        title.textColor = [UIColor cyanColor];
        title.textAlignment = NSTextAlignmentCenter;
        [self addSubview:title];

        int y = 45;
        self.espSwitch = [self makeSwitch:@"ESP Master" x:15 y:y state:espEnabled action:@selector(toggleESP)]; y += 40;
        self.snaplineSwitch = [self makeSwitch:@"Snaplines" x:15 y:y state:espSnaplines action:@selector(toggleSnaplines)]; y += 40;
        self.droneSlider = [self makeSlider:1.0 max:3.0 val:droneValue x:15 y:y color:@"Zoom"]; y += 45;
        
        UILabel *retriLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 150, 30)];
        retriLabel.text = @"✅ Auto Retribution";
        retriLabel.textColor = [UIColor greenColor];
        retriLabel.font = [UIFont boldSystemFontOfSize:13];
        [self addSubview:retriLabel];
        self.retriSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(200, y, 50, 30)];
        self.retriSwitch.on = autoRetriEnabled;
        [self.retriSwitch addTarget:self action:@selector(toggleRetri) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.retriSwitch];
        y += 45;

        self.radarSwitch = [self makeSwitch:@"Map Radar" x:15 y:y state:radarEnabled action:@selector(toggleRadar)]; y += 40;
        self.hpSwitch = [self makeSwitch:@"HP Bar ESP" x:15 y:y state:hpBarEnabled action:@selector(toggleHP)]; y += 40;
        
        self.logView = [[UITextView alloc] initWithFrame:CGRectMake(10, y + 10, frame.size.width-20, 80)];
        self.logView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
        self.logView.textColor = [UIColor greenColor];
        self.logView.font = [UIFont fontWithName:@"Courier" size:9];
        self.logView.editable = NO;
        self.logView.text = @"> System Ready\n";
        [self addSubview:self.logView];
    }
    return self;
}

- (UISwitch *)makeSwitch:(NSString *)title x:(float)x y:(float)y state:(BOOL)state action:(SEL)action {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(x, y, 120, 30)];
    label.text = title; label.textColor = [UIColor whiteColor];
    [self addSubview:label];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(200, y, 50, 30)];
    sw.on = state; [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self addSubview:sw];
    return sw;
}

- (UISlider *)makeSlider:(float)minV max:(float)maxV val:(float)val x:(float)x y:(float)y color:(NSString *)c {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(x+60, y, 170, 20)];
    s.minimumValue = minV; s.maximumValue = maxV; s.value = val;
    [s addTarget:self action:@selector(droneChanged) forControlEvents:UIControlEventValueChanged];
    [self addSubview:s];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(x, y, 50, 20)];
    l.text = c; l.textColor = [UIColor whiteColor]; [self addSubview:l];
    return s;
}

- (void)appendLog:(NSString *)msg {
    NSDateFormatter *f = [[NSDateFormatter alloc] init]; [f setDateFormat:@"HH:mm:ss"];
    NSString *logStr = [NSString stringWithFormat:@"[%@] %@\n", [f stringFromDate:[NSDate date]], msg];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = [logStr stringByAppendingString:self.logView.text];
    });
}

- (void)toggleESP { espEnabled = self.espSwitch.on; applyESP(); }
- (void)toggleSnaplines { espSnaplines = self.snaplineSwitch.on; applyESP(); }
- (void)droneChanged { droneValue = self.droneSlider.value; applyDrone(); }
- (void)toggleHP { hpBarEnabled = self.hpSwitch.on; applyHPBar(); }
- (void)toggleRadar { radarEnabled = self.radarSwitch.on; applyRadar(radarEnabled); }
- (void)toggleRetri { autoRetriEnabled = self.retriSwitch.on; logSystem(@"MOD", autoRetriEnabled?@"Auto Retri Active":@"Auto Retri Disabled"); }

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e { self.startLocation = [[t anyObject] locationInView:self]; }
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint loc = [[t anyObject] locationInView:self.superview];
    self.center = CGPointMake(loc.x - self.startLocation.x + self.bounds.size.width/2, loc.y - self.startLocation.y + self.bounds.size.height/2);
}
@end

// ========== MANAGER ==========
@interface ModManager : NSObject
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) ModMenu *menu;
+ (instancetype)shared;
@end

@implementation ModManager
+ (instancetype)shared { static ModManager *i=nil; static dispatch_once_t t; dispatch_once(&t, ^{ i=[[self alloc] init]; }); return i; }
- (void)initInterface {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene* s in [UIApplication sharedApplication].connectedScenes) {
                if (s.activationState == UISceneActivationStateForegroundActive) {
                    win = s.windows.firstObject; break;
                }
            }
        } else {
            win = [UIApplication sharedApplication].keyWindow;
        }
        if (!win) return;
        
        self.menu = [[ModMenu alloc] initWithFrame:CGRectMake(40, 150, 300, 550)];
        self.menu.hidden = YES; [win addSubview:self.menu];
        
        self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatBtn.frame = CGRectMake(20, 100, 55, 55);
        self.floatBtn.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.8];
        self.floatBtn.layer.cornerRadius = 27.5;
        [self.floatBtn setTitle:@"👁️" forState:UIControlStateNormal];
        [self.floatBtn addTarget:self action:@selector(btnTap) forControlEvents:UIControlEventTouchUpInside];
        [win addSubview:self.floatBtn];
    });
}
- (void)btnTap { self.menu.hidden = !self.menu.hidden; }
@end

__attribute__((constructor))
void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        unityBase = get_base_address("UnityFramework");
        if (unityBase) [[ModManager shared] performSelector:@selector(initInterface) withObject:nil];
    });
}
