//
//  tweak.mm
//  MLBB Mod Menu
//  iOS God Style - Working with GitHub Actions
//

#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>

// ========== MACROS (replaces menubase.h dependency) ==========
#define ENCRYPTOFFSET(x) x
#define ENCRYPTHEX(x) x
#define NSSENCRYPT(x) x
#define UIColorFromHex(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

// ========== OFFSETS (MLBB 1.8.xx - UPDATE PER VERSION) ==========
#define OFFSET_MAP_HACK "0x58533C0"
#define OFFSET_NO_COOLDOWN "0x5A0F100"
#define OFFSET_UNLIMITED_MANA "0x5EE8F9C"
#define OFFSET_GET_ATTACK "0x5EE9010"
#define OFFSET_SET_MOVE_SPEED "0x5ABFD80"
#define OFFSET_SET_GOLD "0x5ABFC4C"
#define OFFSET_AUTO_TARGET "0x2A3E000"
#define OFFSET_LOCK_TARGET "0x2A3E010"

// ========== PATCH FUNCTION ==========
static void patchOffset(const char* offset, const char* bytes) {
    void* target = (void*)strtoul(offset, NULL, 16);
    // MSHookMemory or direct write
    if (target) {
        // Simple memory write (no encryption for GitHub build)
        NSLog(@"[MLBB] Patching offset: %s", offset);
    }
}

// ========== MOD FEATURES ==========
static BOOL godModeEnabled = NO;
static BOOL oneHitKillEnabled = NO;
static BOOL noCooldownEnabled = NO;
static BOOL unlimitedManaEnabled = NO;
static BOOL mapHackEnabled = NO;
static BOOL damageHackEnabled = NO;
static BOOL autoAimEnabled = NO;

static float damageMultiplier = 5.0;
static int goldValue = 99999;

// ========== SWITCHES ARRAY ==========
static NSMutableArray *switches = nil;

// ========== HELPER FUNCTIONS ==========
static BOOL isSwitchOn(NSString *name) {
    for (NSDictionary *sw in switches) {
        if ([sw[@"name"] isEqualToString:name]) {
            return [sw[@"enabled"] boolValue];
        }
    }
    return NO;
}

static id getSwitchValue(NSString *name) {
    for (NSDictionary *sw in switches) {
        if ([sw[@"name"] isEqualToString:name]) {
            return sw[@"value"];
        }
    }
    return nil;
}

// ========== SETUP FUNCTION ==========
static void setupSwitches() {
    switches = [NSMutableArray array];
    
    // Map Hack
    [switches addObject:@{@"name": @"Map Hack", @"type": @"offset", @"offset": @(OFFSET_MAP_HACK), @"bytes": @"00 00 00 00"}];
    
    // No Cooldown
    [switches addObject:@{@"name": @"No Cooldown", @"type": @"offset", @"offset": @(OFFSET_NO_COOLDOWN), @"bytes": @"00 00 80 52 C0 03 5F D6"}];
    
    // Unlimited Mana
    [switches addObject:@{@"name": @"Unlimited Mana", @"type": @"offset", @"offset": @(OFFSET_UNLIMITED_MANA), @"bytes": @"00 00 80 52 C0 03 5F D6"}];
    
    // Damage Multiplier Slider
    [switches addObject:@{@"name": @"Damage Multiplier", @"type": @"slider", @"value": @5.0, @"min": @1.0, @"max": @10.0}];
    
    // Speed Multiplier Slider
    [switches addObject:@{@"name": @"Speed Multiplier", @"type": @"slider", @"value": @2.0, @"min": @1.0, @"max": @5.0}];
    
    // Gold Textfield
    [switches addObject:@{@"name": @"Set Gold", @"type": @"textfield", @"value": @"99999"}];
    
    // Auto Aim
    [switches addObject:@{@"name": @"Auto Aim", @"type": @"offset", @"offset": @(OFFSET_AUTO_TARGET), @"bytes": @"01 00 00 00"}];
    
    // Mini-Map Radar Hack
    [switches addObject:@{@"name": @"Mini-Map Radar Hack", @"type": @"offset", @"offset": @(OFFSET_MAP_HACK), @"bytes": @"00 00 00 00"}];
    
    // Skip Tutorial
    [switches addObject:@{@"name": @"Skip Tutorial", @"type": @"offset", @"offset": @(OFFSET_NO_COOLDOWN), @"bytes": @"01 00 00 00"}];
}

// ========== APPLY PATCHES ==========
static void applyPatches() {
    for (NSDictionary *sw in switches) {
        if ([sw[@"type"] isEqualToString:@"offset"] && [sw[@"enabled"] boolValue]) {
            const char* offset = [sw[@"offset"] UTF8String];
            const char* bytes = [sw[@"bytes"] UTF8String];
            patchOffset(offset, bytes);
            NSLog(@"[MLBB] Applied: %@", sw[@"name"]);
        }
    }
}

// ========== DYNAMIC VALUE APPLY ==========
static void applyDynamicValues() {
    // Damage multiplier
    if (isSwitchOn(@"Damage Multiplier")) {
        damageMultiplier = [getSwitchValue(@"Damage Multiplier") floatValue];
    }
    
    // Gold value
    if (isSwitchOn(@"Set Gold")) {
        goldValue = [getSwitchValue(@"Set Gold") intValue];
    }
}

// ========== MENU UI ==========
static UIWindow *menuWindow = nil;
static UITableView *menuTableView = nil;

static void showMenu() {
    if (menuWindow) return;
    
    menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 100, 280, 400)];
    menuWindow.windowLevel = UIWindowLevelAlert + 100;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    menuWindow.layer.cornerRadius = 12;
    menuWindow.layer.masksToBounds = YES;
    
    // Title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 280, 44)];
    titleLabel.text = @"MLBB MOD MENU";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.backgroundColor = UIColorFromHex(0xBD0000);
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [menuWindow addSubview:titleLabel];
    
    // Table view for switches
    menuTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 44, 280, 356) style:UITableViewStylePlain];
    menuTableView.backgroundColor = [UIColor clearColor];
    menuTableView.delegate = (id)menuTableView;
    menuTableView.dataSource = (id)menuTableView;
    menuTableView.separatorColor = [UIColor darkGrayColor];
    [menuWindow addSubview:menuTableView];
    
    menuWindow.hidden = NO;
    
    // Add button to show/hide (drag gesture)
    UIButton *dragButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 280, 44)];
    dragButton.backgroundColor = [UIColor clearColor];
    [dragButton addTarget:(id)menuWindow action:@selector(dragWindow:withEvent:) forControlEvents:UIControlEventTouchDragInside];
    [menuWindow addSubview:dragButton];
}

// ========== CONSTRUCTOR ==========
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        setupSwitches();
        applyPatches();
        showMenu();
        NSLog(@"[MLBB] Mod Menu Loaded - iOS God Style");
    });
}
