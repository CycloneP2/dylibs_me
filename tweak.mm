// tweak.mm
// MLBB Mod - Full radar, rank spoof, ban bypass, draggable GUI with TOGGLES
// Offsets from dump: 0x91cc1 to 0xba0eb

#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach/mach.h>

// ============================================
// OFFSETS (iOS MLBB specific version)
// ============================================
#define OFF_TUTORIAL_PATCH          0x939cc
#define OFF_TOGGLE_MENU             0x9205f
#define OFF_HIDE_DEBUG_MENU         0x91de5
#define OFF_POPULATE_RADAR_TAB      0x92465
#define OFF_TAB_RADAR               0x9280b
#define OFF_RADAR_EDIT_CHANGED      0x92c76
#define OFF_RADAR_X                 0x92c94
#define OFF_RADAR_Y                 0x92ca3
#define OFF_RADAR_SIZE              0x92cb2
#define OFF_GLOBAL_RANK             0x9cf55
#define OFF_LOCAL_RANK              0x9cf70
#define OFF_CULTIVATE               0x9cf8a
#define OFF_WINRATE_SPOOFER         0x9cfa4
#define OFF_BAN_BYPASS              0x961b8
#define OFF_FREE_SKINS              0x961e7
#define OFF_DOWNLOAD_BYPASS         0x9621c
#define OFF_MEGA_PATCH              0x96254
#define OFF_TIME_GET                0x9cd26

static uintptr_t unityBase = 0;
static UIButton *draggableButton = nil;
static UIView *settingsPanel = nil;
static BOOL panelVisible = NO;

// Feature states (saved to UserDefaults)
static BOOL tutorialEnabled = YES;
static BOOL radarEnabled = YES;
static BOOL rankSpoofEnabled = YES;
static BOOL banBypassEnabled = YES;
static BOOL freeSkinsEnabled = YES;
static BOOL timeFreezeEnabled = YES;

// ============================================
// DRAGGABLE BUTTON CLASS
// ============================================
@interface DraggableButton : UIButton {
    CGPoint startLocation;
}
@end

@implementation DraggableButton
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    startLocation = [[touches anyObject] locationInView:self.superview];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint currentLocation = [[touches anyObject] locationInView:self.superview];
    CGRect frame = self.frame;
    frame.origin.x += currentLocation.x - startLocation.x;
    frame.origin.y += currentLocation.y - startLocation.y;
    self.frame = frame;
    
    [[NSUserDefaults standardUserDefaults] setFloat:frame.origin.x forKey:@"MLBB_ButtonX"];
    [[NSUserDefaults standardUserDefaults] setFloat:frame.origin.y forKey:@"MLBB_ButtonY"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
@end

// ============================================
// MEMORY PATCHING HELPERS
// ============================================
void writeInt(uintptr_t address, int value) {
    vm_protect(mach_task_self(), (void *)address, sizeof(int), 0, VM_PROT_READ | VM_PROT_WRITE);
    *(int *)address = value;
}

void writeByte(uintptr_t address, uint8_t value) {
    vm_protect(mach_task_self(), (void *)address, sizeof(uint8_t), 0, VM_PROT_READ | VM_PROT_WRITE);
    *(uint8_t *)address = value;
}

void patchTutorial(bool enable) {
    if (!unityBase) return;
    uintptr_t addr = unityBase + OFF_TUTORIAL_PATCH;
    if (enable) {
        unsigned char bytes[] = {0x20, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6}; // mov x0,#1; ret
        vm_protect(mach_task_self(), (void *)addr, 8, 0, VM_PROT_READ | VM_PROT_WRITE);
        memcpy((void *)addr, bytes, 8);
    } else {
        // Restore original bytes (approximate NOP or original - depends on game version)
        unsigned char bytes[] = {0x00, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6}; // mov x0,#0; ret
        vm_protect(mach_task_self(), (void *)addr, 8, 0, VM_PROT_READ | VM_PROT_WRITE);
        memcpy((void *)addr, bytes, 8);
    }
}

void applyRadar(bool enable) {
    if (!unityBase) return;
    if (enable) {
        writeInt(unityBase + OFF_RADAR_X, 9999);
        writeInt(unityBase + OFF_RADAR_Y, 9999);
        writeInt(unityBase + OFF_RADAR_SIZE, 200);
        writeByte(unityBase + OFF_TAB_RADAR, 0x01);
    } else {
        writeInt(unityBase + OFF_RADAR_X, 0);
        writeInt(unityBase + OFF_RADAR_Y, 0);
        writeInt(unityBase + OFF_RADAR_SIZE, 100);
        writeByte(unityBase + OFF_TAB_RADAR, 0x00);
    }
}

void applyRankSpoof(bool enable) {
    if (!unityBase) return;
    if (enable) {
        writeInt(unityBase + OFF_GLOBAL_RANK, 27);
        writeInt(unityBase + OFF_LOCAL_RANK, 1);
        writeInt(unityBase + OFF_CULTIVATE, 9999);
    } else {
        writeInt(unityBase + OFF_GLOBAL_RANK, 0);
        writeInt(unityBase + OFF_LOCAL_RANK, 0);
        writeInt(unityBase + OFF_CULTIVATE, 0);
    }
}

void applyBanBypass(bool enable) {
    if (!unityBase) return;
    writeByte(unityBase + OFF_BAN_BYPASS, enable ? 0x01 : 0x00);
    writeByte(unityBase + OFF_MEGA_PATCH, enable ? 0x01 : 0x00);
}

void applyFreeSkins(bool enable) {
    if (!unityBase) return;
    writeByte(unityBase + OFF_FREE_SKINS, enable ? 0x01 : 0x00);
    writeByte(unityBase + OFF_DOWNLOAD_BYPASS, enable ? 0x01 : 0x00);
}

// ============================================
// HOOKED FUNCTIONS
// ============================================
float (*orig_get_time)();
float hooked_get_time() {
    if (timeFreezeEnabled) return 0.0f;
    return orig_get_time();
}

void (*orig_populateRadarTab)();
void hooked_populateRadarTab() {
    orig_populateRadarTab();
    if (radarEnabled) {
        writeInt(unityBase + OFF_RADAR_X, 9999);
    }
}

void (*orig_radarEditChanged)(void *self, SEL _cmd, id sender);
void hooked_radarEditChanged(void *self, SEL _cmd, id sender) {
    if (radarEnabled) {
        writeInt(unityBase + OFF_RADAR_X, 9999);
        writeInt(unityBase + OFF_RADAR_Y, 9999);
    }
    orig_radarEditChanged(self, _cmd, sender);
}

bool (*orig_toggleMenu)();
bool hooked_toggleMenu() {
    return true; // Always allow debug menu
}

// ============================================
// SETTINGS PANEL WITH TOGGLES
// ============================================
void applyAllSettings() {
    patchTutorial(tutorialEnabled);
    applyRadar(radarEnabled);
    applyRankSpoof(rankSpoofEnabled);
    applyBanBypass(banBypassEnabled);
    applyFreeSkins(freeSkinsEnabled);
    // timeFreezeEnabled is checked inside hooked_get_time
}

void saveSettings() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:tutorialEnabled forKey:@"MLBB_Tutorial"];
    [defaults setBool:radarEnabled forKey:@"MLBB_Radar"];
    [defaults setBool:rankSpoofEnabled forKey:@"MLBB_RankSpoof"];
    [defaults setBool:banBypassEnabled forKey:@"MLBB_BanBypass"];
    [defaults setBool:freeSkinsEnabled forKey:@"MLBB_FreeSkins"];
    [defaults setBool:timeFreezeEnabled forKey:@"MLBB_TimeFreeze"];
    [defaults synchronize];
}

void loadSettings() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    tutorialEnabled = [defaults objectForKey:@"MLBB_Tutorial"] ? [defaults boolForKey:@"MLBB_Tutorial"] : YES;
    radarEnabled = [defaults objectForKey:@"MLBB_Radar"] ? [defaults boolForKey:@"MLBB_Radar"] : YES;
    rankSpoofEnabled = [defaults objectForKey:@"MLBB_RankSpoof"] ? [defaults boolForKey:@"MLBB_RankSpoof"] : YES;
    banBypassEnabled = [defaults objectForKey:@"MLBB_BanBypass"] ? [defaults boolForKey:@"MLBB_BanBypass"] : YES;
    freeSkinsEnabled = [defaults objectForKey:@"MLBB_FreeSkins"] ? [defaults boolForKey:@"MLBB_FreeSkins"] : YES;
    timeFreezeEnabled = [defaults objectForKey:@"MLBB_TimeFreeze"] ? [defaults boolForKey:@"MLBB_TimeFreeze"] : YES;
}

void showSettingsPanel() {
    if (panelVisible) {
        [settingsPanel removeFromSuperview];
        panelVisible = NO;
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;
        
        if (settingsPanel) {
            [settingsPanel removeFromSuperview];
        }
        
        settingsPanel = [[UIView alloc] initWithFrame:CGRectMake(20, 150, 280, 400)];
        settingsPanel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        settingsPanel.layer.cornerRadius = 15;
        settingsPanel.layer.borderWidth = 1;
        settingsPanel.layer.borderColor = [UIColor greenColor].CGColor;
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 280, 30)];
        title.text = @"MLBB Mod Settings";
        title.textColor = [UIColor greenColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:18];
        [settingsPanel addSubview:title];
        
        NSArray *titles = @[@"Tutorial Bypass", @"Radar Hack", @"Rank Spoof", @"Ban Bypass", @"Free Skins", @"Time Freeze"];
        NSArray *keys = @[@(tutorialEnabled), @(radarEnabled), @(rankSpoofEnabled), @(banBypassEnabled), @(freeSkinsEnabled), @(timeFreezeEnabled)];
        
        for (int i = 0; i < titles.count; i++) {
            UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(200, 50 + i * 50, 50, 30)];
            toggle.tag = i;
            toggle.on = [keys[i] boolValue];
            [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
            
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 50 + i * 50, 170, 30)];
            label.text = titles[i];
            label.textColor = [UIColor whiteColor];
            label.font = [UIFont systemFontOfSize:14];
            
            [settingsPanel addSubview:label];
            [settingsPanel addSubview:toggle];
        }
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(90, 350, 100, 40);
        [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor darkGrayColor];
        closeBtn.layer.cornerRadius = 8;
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
        [settingsPanel addSubview:closeBtn];
        
        [keyWindow addSubview:settingsPanel];
        panelVisible = YES;
    });
}

void toggleChanged(UISwitch *sender) {
    switch (sender.tag) {
        case 0: tutorialEnabled = sender.on; patchTutorial(tutorialEnabled); break;
        case 1: radarEnabled = sender.on; applyRadar(radarEnabled); break;
        case 2: rankSpoofEnabled = sender.on; applyRankSpoof(rankSpoofEnabled); break;
        case 3: banBypassEnabled = sender.on; applyBanBypass(banBypassEnabled); break;
        case 4: freeSkinsEnabled = sender.on; applyFreeSkins(freeSkinsEnabled); break;
        case 5: timeFreezeEnabled = sender.on; break;
    }
    saveSettings();
}

void closePanel() {
    [settingsPanel removeFromSuperview];
    panelVisible = NO;
}

// ============================================
// CREATE DRAGGABLE BUTTON
// ============================================
void createDraggableButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;
        
        if (draggableButton) [draggableButton removeFromSuperview];
        
        draggableButton = [DraggableButton buttonWithType:UIButtonTypeSystem];
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        float savedX = [defaults floatForKey:@"MLBB_ButtonX"];
        float savedY = [defaults floatForKey:@"MLBB_ButtonY"];
        if (savedX == 0 && savedY == 0) { savedX = 20; savedY = 100; }
        
        draggableButton.frame = CGRectMake(savedX, savedY, 220, 45);
        [draggableButton setTitle:@"🔧 MLBB Mod | Settings" forState:UIControlStateNormal];
        draggableButton.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.85];
        draggableButton.layer.cornerRadius = 12;
        draggableButton.layer.borderWidth = 1;
        draggableButton.layer.borderColor = [UIColor greenColor].CGColor;
        draggableButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [draggableButton setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        [draggableButton addTarget:self action:@selector(showSettingsPanel) forControlEvents:UIControlEventTouchUpInside];
        
        [keyWindow addSubview:draggableButton];
    });
}

// ============================================
// INITIALIZATION
// ============================================
__attribute__((constructor))
void init() {
    unityBase = (uintptr_t)dlopen("/private/var/containers/Bundle/Application/*/mlbb.app/Frameworks/UnityFramework.framework/UnityFramework", RTLD_LAZY);
    if (!unityBase) {
        unityBase = (uintptr_t)dlopen("/var/containers/Bundle/Application/*/mlbb.app/Frameworks/UnityFramework.framework/UnityFramework", RTLD_LAZY);
    }
    if (!unityBase) return;
    
    loadSettings();
    applyAllSettings();
    
    MSHookFunction((void *)(unityBase + OFF_TIME_GET), (void *)hooked_get_time, (void **)&orig_get_time);
    MSHookFunction((void *)(unityBase + OFF_POPULATE_RADAR_TAB), (void *)hooked_populateRadarTab, (void **)&orig_populateRadarTab);
    MSHookFunction((void *)(unityBase + OFF_RADAR_EDIT_CHANGED), (void *)hooked_radarEditChanged, (void **)&orig_radarEditChanged);
    MSHookFunction((void *)(unityBase + OFF_TOGGLE_MENU), (void *)hooked_toggleMenu, (void **)&orig_toggleMenu);
    
    createDraggableButton();
    
    NSLog(@"[MLBB Mod] Loaded with per-feature toggles. Tap button to open settings.");
}
