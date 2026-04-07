// tweak.mm - MLBB PRO MAX (Full ESP + Radar + Menu)
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>

// ========== OFFSETS (UPDATED WITH ESP TABLE) ==========
#define OFF_TUTORIAL_PATCH          0x939cc
#define OFF_RADAR_X                 0x92c94
#define OFF_RADAR_Y                 0x92ca3
#define OFF_RADAR_SIZE              0x92cb2
#define OFF_BAN_BYPASS              0x961b8

// ESP Offsets from table
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
#define OFF_DRONE_VIEW              0x9AA10 // Drone View / FOV Offset
#define OFF_HP_BAR                  0x9BC50 // HP Bar Visibility Offset

static uintptr_t unityBase = 0;

// Feature states
static BOOL tutorialEnabled = NO, radarEnabled = NO, banBypassEnabled = NO;
static BOOL espEnabled = NO, espSnaplines = NO, espMonster = NO, espShowTeam = YES;
static BOOL droneEnabled = NO, hpBarEnabled = NO;
static float droneValue = 1.0; // 1.0 = Default, 1.5-2.0 = Drone
static float espEnemyR = 1.0, espEnemyG = 0.0, espEnemyB = 0.0;
static float espAllyR = 0.0, espAllyG = 1.0, espAllyB = 0.0;

// ========== MEMORY HELPERS ==========
uintptr_t get_base_address(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strstr(_dyld_get_image_name(i), name)) 
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

// Forward declaration
@interface ModMenu : UIView
- (void)appendLog:(NSString *)msg;
@end
extern ModMenu *globalMenu;

void logSystem(NSString *type, NSString *msg) {
    NSString *full = [NSString stringWithFormat:@"[%@] %@", type, msg];
    NSLog(@"%@", full);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (globalMenu) [globalMenu appendLog:full];
    });
}

// ========== MEMORY HELPERS WITH ERRORS ==========
BOOL writeFloat(uintptr_t addr, float val) {
    kern_return_t err = vm_protect(mach_task_self(), addr, sizeof(float), 0, VM_PROT_READ | VM_PROT_WRITE);
    if (err == KERN_SUCCESS) {
        *(float *)addr = val;
        logSystem(@"OK", [NSString stringWithFormat:@"Float 0x%lX = %.2f", (long)addr, val]);
        return YES;
    }
    logSystem(@"ERROR", [NSString stringWithFormat:@"Float 0x%lX Fail (%d)", (long)addr, err]);
    return NO;
}

BOOL writeInt(uintptr_t addr, int val) {
    kern_return_t err = vm_protect(mach_task_self(), addr, sizeof(int), 0, VM_PROT_READ | VM_PROT_WRITE);
    if (err == KERN_SUCCESS) {
        *(int *)addr = val;
        logSystem(@"OK", [NSString stringWithFormat:@"Int 0x%lX = %d", (long)addr, val]);
        return YES;
    }
    logSystem(@"ERROR", [NSString stringWithFormat:@"Int 0x%lX Fail (%d)", (long)addr, err]);
    return NO;
}

BOOL writeByte(uintptr_t addr, unsigned char val) {
    kern_return_t err = vm_protect(mach_task_self(), addr, 1, 0, VM_PROT_READ | VM_PROT_WRITE);
    if (err == KERN_SUCCESS) {
        *(unsigned char *)addr = val;
        logSystem(@"OK", [NSString stringWithFormat:@"Byte 0x%lX = 0x%02X", (long)addr, val]);
        return YES;
    }
    logSystem(@"ERROR", [NSString stringWithFormat:@"Byte 0x%lX Fail (%d)", (long)addr, err]);
    return NO;
}

BOOL writePatch(uintptr_t addr, unsigned char *patch, size_t size) {
    kern_return_t err = vm_protect(mach_task_self(), addr, size, 0, VM_PROT_READ | VM_PROT_WRITE);
    if (err == KERN_SUCCESS) {
        memcpy((void *)addr, patch, size);
        logSystem(@"OK", [NSString stringWithFormat:@"Patch 0x%lX (%ld bytes)", (long)addr, size]);
        return YES;
    }
    logSystem(@"ERROR", [NSString stringWithFormat:@"Patch 0x%lX Fail (%d)", (long)addr, err]);
    return NO;
}

// ========== ESP FUNCTIONS ==========
void applyESP() {
    if (!unityBase) return;
    
    // Master ESP toggle
    writeByte(unityBase + OFF_ESP_ENABLED, espEnabled ? 1 : 0);
    
    if (espEnabled) {
        // Enemy color (Red)
        writeFloat(unityBase + OFF_ESP_ENEMY_R, espEnemyR);
        writeFloat(unityBase + OFF_ESP_ENEMY_G, espEnemyG);
        writeFloat(unityBase + OFF_ESP_ENEMY_B, espEnemyB);
        
        // Ally color (Green)
        writeFloat(unityBase + OFF_ESP_ALLY_R, espAllyR);
        writeFloat(unityBase + OFF_ESP_ALLY_G, espAllyG);
        writeFloat(unityBase + OFF_ESP_ALLY_B, espAllyB);
        
        // Snaplines
        writeByte(unityBase + OFF_ESP_SNAPLINES, espSnaplines ? 1 : 0);
        
        // Monster ESP
        writeByte(unityBase + OFF_ESP_MONSTER, espMonster ? 1 : 0);
        writeByte(unityBase + OFF_MONSTER_ESP, espMonster ? 1 : 0);
        
        // Show team
        writeByte(unityBase + OFF_ESP_SHOW_TEAM, espShowTeam ? 1 : 0);
        
        // SESP
        writeByte(unityBase + OFF_SESP, 1);
    }
}

void applyDrone() {
    if (!unityBase) return;
    // Common drone factor (default is around 10-15f, we scale it)
    writeFloat(unityBase + OFF_DRONE_VIEW, droneEnabled ? (15.0f * droneValue) : 15.0f);
}

void applyHPBar() {
    if (!unityBase) return;
    writeByte(unityBase + OFF_HP_BAR, hpBarEnabled ? 1 : 0);
}

// ========== EXISTING MOD LOGIC ==========
void applyTutorial(BOOL enable) {
    if (!unityBase) { logSystem(@"SYSTEM", @"UnityBase Missing!"); return; }
    uintptr_t addr = unityBase + OFF_TUTORIAL_PATCH;
    if (enable) {
        unsigned char patch[] = {0x20, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6};
        writePatch(addr, patch, 8);
    } else {
        unsigned char orig[] = {0x00, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6};
        writePatch(addr, orig, 8);
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
    writeByte(unityBase + OFF_BAN_BYPASS, enable ? 0x01 : 0x00);
}

// ========== UI MENU ==========
@interface ModMenu : UIView
@property (nonatomic, strong) UISwitch *espSwitch, *snaplineSwitch, *monsterSwitch;
@property (nonatomic, strong) UISwitch *tutorialSwitch, *radarSwitch, *banSwitch, *hpSwitch, *droneSwitch;
@property (nonatomic, strong) UISlider *enemyRSlider, *enemyGSlider, *enemyBSlider, *droneSlider;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, assign) CGPoint startLocation;
- (void)appendLog:(NSString *)msg;
@end

static ModMenu *globalMenu = nil;

@implementation ModMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        globalMenu = self;
        self.backgroundColor = [UIColor clearColor];
        
        // Blur background
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.frame = self.bounds;
        blurView.layer.cornerRadius = 20;
        blurView.layer.masksToBounds = YES;
        [self addSubview:blurView];
        
        // Title
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, frame.size.width, 28)];
        title.text = @"🔥 MLBB PRO MAX ESP 🔥";
        title.textColor = [UIColor cyanColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:title];
        
        int y = 45;
        
        // ESP Master Toggle
        UILabel *espLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 120, 30)];
        espLabel.text = @"ESP MASTER";
        espLabel.textColor = [UIColor whiteColor];
        espLabel.font = [UIFont boldSystemFontOfSize:13];
        [self addSubview:espLabel];
        self.espSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(200, y, 50, 30)];
        self.espSwitch.on = espEnabled;
        self.espSwitch.onTintColor = [UIColor redColor];
        [self.espSwitch addTarget:self action:@selector(toggleESP) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.espSwitch];
        y += 40;
        
        // Snaplines
        UILabel *snapLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 120, 30)];
        snapLabel.text = @"Snaplines";
        snapLabel.textColor = [UIColor whiteColor];
        [self addSubview:snapLabel];
        self.snaplineSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(200, y, 50, 30)];
        self.snaplineSwitch.on = espSnaplines;
        [self.snaplineSwitch addTarget:self action:@selector(toggleSnaplines) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.snaplineSwitch];
        y += 40;
        
        // Monster ESP
        UILabel *monsterLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 120, 30)];
        monsterLabel.text = @"Monster ESP";
        monsterLabel.textColor = [UIColor whiteColor];
        [self addSubview:monsterLabel];
        self.monsterSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(200, y, 50, 30)];
        self.monsterSwitch.on = espMonster;
        [self.monsterSwitch addTarget:self action:@selector(toggleMonster) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.monsterSwitch];
        y += 40;
        
        // Enemy Color Sliders
        UILabel *enemyColorLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 180, 20)];
        enemyColorLabel.text = @"Enemy RGB";
        enemyColorLabel.textColor = [UIColor redColor];
        enemyColorLabel.font = [UIFont systemFontOfSize:11];
        [self addSubview:enemyColorLabel];
        y += 22;
        
        self.enemyRSlider = [self makeSlider:0.0 max:1.0 val:espEnemyR x:15 y:y color:@"R"];
        self.enemyGSlider = [self makeSlider:0.0 max:1.0 val:espEnemyG x:15 y:y+25 color:@"G"];
        self.enemyBSlider = [self makeSlider:0.0 max:1.0 val:espEnemyB x:15 y:y+50 color:@"B"];
        y += 85;
        
        // --- DRONE VIEW ---
        UILabel *droneLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 120, 30)];
        droneLabel.text = @"Drone View (FOV)";
        droneLabel.textColor = [UIColor cyanColor];
        [self addSubview:droneLabel];
        self.droneSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(200, y, 50, 30)];
        self.droneSwitch.on = droneEnabled;
        [self.droneSwitch addTarget:self action:@selector(toggleDrone) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.droneSwitch];
        y += 35;
        self.droneSlider = [self makeSlider:1.0 max:3.0 val:droneValue x:15 y:y color:@"Zoom"];
        y += 40;

        // Existing features
        UILabel *otherLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 200, 20)];
        otherLabel.text = @"--- OTHER HACKS ---";
        otherLabel.textColor = [UIColor yellowColor];
        [self addSubview:otherLabel];
        y += 25;
        
        self.hpSwitch = [self makeSwitch:@"Show HP Bar" x:15 y:y state:hpBarEnabled action:@selector(toggleHP)];
        y += 40;
        self.tutorialSwitch = [self makeSwitch:@"Skip Tutorial" x:15 y:y state:tutorialEnabled action:@selector(toggleTutorial)];
        y += 40;
        self.radarSwitch = [self makeSwitch:@"Map Radar" x:15 y:y state:radarEnabled action:@selector(toggleRadar)];
        y += 40;
        self.banSwitch = [self makeSwitch:@"Anti-Ban" x:15 y:y state:banBypassEnabled action:@selector(toggleBan)];
        y += 50;
        
        // Log view
        self.logView = [[UITextView alloc] initWithFrame:CGRectMake(10, y, frame.size.width-20, 60)];
        self.logView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        self.logView.textColor = [UIColor greenColor];
        self.logView.font = [UIFont fontWithName:@"Courier" size:9];
        self.logView.editable = NO;
        self.logView.text = @"> Ready\n";
        [self addSubview:self.logView];
        
        // Resize frame to fit all content
        CGRect newFrame = self.frame;
        newFrame.size.height = y + 70;
        self.frame = newFrame;
    }
    return self;
}

- (UISlider *)makeSlider:(float)minVal max:(float)maxVal val:(float)val x:(float)x y:(float)y color:(NSString *)c {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(x+50, y, 180, 20)];
    slider.minimumValue = minVal;
    slider.maximumValue = maxVal;
    slider.value = val;
    slider.tag = [c intValue];
    [slider addTarget:self action:@selector(enemyColorChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:slider];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(x, y, 40, 20)];
    label.text = c;
    label.textColor = [UIColor lightGrayColor];
    label.font = [UIFont systemFontOfSize:12];
    [self addSubview:label];
    return slider;
}

- (UISwitch *)makeSwitch:(NSString *)title x:(float)x y:(float)y state:(BOOL)state action:(SEL)action {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(x, y, 120, 30)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:13];
    [self addSubview:label];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(x+140, y, 50, 30)];
    sw.on = state;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self addSubview:sw];
    return sw;
}

- (void)toggleESP { espEnabled = self.espSwitch.on; applyESP(); [self appendLog:[NSString stringWithFormat:@"ESP %@", espEnabled?@"ON":@"OFF"]]; }
- (void)toggleSnaplines { espSnaplines = self.snaplineSwitch.on; applyESP(); [self appendLog:[NSString stringWithFormat:@"Snaplines %@", espSnaplines?@"ON":@"OFF"]]; }
- (void)toggleMonster { espMonster = self.monsterSwitch.on; applyESP(); [self appendLog:[NSString stringWithFormat:@"Monster ESP %@", espMonster?@"ON":@"OFF"]]; }
- (void)enemyColorChanged:(UISlider *)s { espEnemyR = self.enemyRSlider.value; espEnemyG = self.enemyGSlider.value; espEnemyB = self.enemyBSlider.value; applyESP(); }

- (void)toggleDrone { droneEnabled = self.droneSwitch.on; applyDrone(); [self appendLog:[NSString stringWithFormat:@"Drone View %@", droneEnabled?@"Active":@"Off"]]; }
- (void)droneChanged { droneValue = self.droneSlider.value; applyDrone(); }
- (void)toggleHP { hpBarEnabled = self.hpSwitch.on; applyHPBar(); [self appendLog:[NSString stringWithFormat:@"HP Bar %@", hpBarEnabled?@"Visible":@"Hidden"]]; }

- (void)toggleTutorial { tutorialEnabled = self.tutorialSwitch.on; applyTutorial(tutorialEnabled); [self appendLog:[NSString stringWithFormat:@"Tutorial %@", tutorialEnabled?@"Skipped":@"Normal"]]; }
- (void)toggleRadar { radarEnabled = self.radarSwitch.on; applyRadar(radarEnabled); [self appendLog:[NSString stringWithFormat:@"Radar %@", radarEnabled?@"Full":@"Normal"]]; }
- (void)toggleBan { banBypassEnabled = self.banSwitch.on; applyBanBypass(banBypassEnabled); [self appendLog:[NSString stringWithFormat:@"Anti-Ban %@", banBypassEnabled?@"Active":@"Off"]]; }

- (void)appendLog:(NSString *)msg {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f setDateFormat:@"HH:mm:ss"];
    NSString *logStr = [NSString stringWithFormat:@"[%@] %@\n", [f stringFromDate:[NSDate date]], msg];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = [logStr stringByAppendingString:self.logView.text];
        if (self.logView.text.length > 2000) {
            self.logView.text = [self.logView.text substringToIndex:2000];
        }
    });
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)e { self.startLocation = [[touches anyObject] locationInView:self]; }
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)e {
    CGPoint loc = [[touches anyObject] locationInView:self.superview];
    self.center = CGPointMake(loc.x - self.startLocation.x + self.bounds.size.width/2, loc.y - self.startLocation.y + self.bounds.size.height/2);
}
@end

// ========== MANAGER ==========
@interface ModManager : NSObject
@property (nonatomic, strong) UIButton *floatBtn;
@property (nonatomic, strong) ModMenu *menu;
+ (instancetype)shared;
- (void)initInterface;
@end

@implementation ModManager
+ (instancetype)shared { static ModManager *i=nil; static dispatch_once_t t; dispatch_once(&t, ^{ i=[[self alloc] init]; }); return i; }
- (void)initInterface {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        if (!win) return;
        
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        tutorialEnabled = [d boolForKey:@"ML_Tutorial"];
        radarEnabled = [d boolForKey:@"ML_Radar"];
        banBypassEnabled = [d boolForKey:@"ML_Ban"];
        espEnabled = [d boolForKey:@"ML_ESP"];
        espSnaplines = [d boolForKey:@"ML_Snap"];
        espMonster = [d boolForKey:@"ML_Monster"];
        droneEnabled = [d boolForKey:@"ML_Drone"];
        droneValue = [d floatForKey:@"ML_DroneVal"] ?: 1.0;
        hpBarEnabled = [d boolForKey:@"ML_HP"];
        
        self.menu = [[ModMenu alloc] initWithFrame:CGRectMake(40, 150, 300, 600)];
        self.menu.hidden = YES;
        [win addSubview:self.menu];
        
        applyTutorial(tutorialEnabled);
        applyRadar(radarEnabled);
        applyBanBypass(banBypassEnabled);
        applyESP();
        applyDrone();
        applyHPBar();
        
        self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatBtn.frame = CGRectMake(20, 100, 55, 55);
        self.floatBtn.backgroundColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.9];
        self.floatBtn.layer.cornerRadius = 27.5;
        [self.floatBtn setTitle:@"👁️" forState:UIControlStateNormal];
        [self.floatBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.floatBtn.titleLabel.font = [UIFont systemFontOfSize:30];
        [self.floatBtn addTarget:self action:@selector(btnTap) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self.floatBtn addGestureRecognizer:p];
        [win addSubview:self.floatBtn];
    });
}
- (void)btnTap { self.menu.hidden = !self.menu.hidden; }
- (void)pan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:v.superview];
}
@end

__attribute__((constructor))
void init() {
    logSystem(@"INIT", @"Injecting Tweak...");
    dlopen("@executable_path/Frameworks/UnityFramework.framework/UnityFramework", RTLD_LAZY);
    unityBase = get_base_address("UnityFramework");
    if (unityBase) {
        logSystem(@"OK", [NSString stringWithFormat:@"UnityBase Found: 0x%lX", (long)unityBase]);
        [[ModManager shared] initInterface];
    } else {
        logSystem(@"ERROR", @"UnityFramework Not Found! Check Loader.");
    }
}
