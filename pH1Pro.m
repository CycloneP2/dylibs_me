#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <sys/syscall.h>
#import <mach/mach.h>

// --- CONFIGURATION & OFFSETS ---
#define PH1_DYLIB_NAME      "ph1mlbb.dylib"
#define UNITY_NAME          "UnityFramework"

// Game RVAs
#define RVA_CAMERA_MAIN     0x89FF130
#define RVA_W2S             0x89FE040
#define RVA_GET_BM          0x6A48A98 
#define RVA_GET_ATK_DIS     0x4FEC06C

// Entity Offsets (Verified from dump.cs)
#define OFF_BM_PLAYER_LIST  0x78    // BattleManager -> m_ShowPlayers
#define OFF_BM_LOCAL_PLAYER 0x50    // BattleManager -> m_LocalPlayerShow
#define OFF_ENTITY_POS      0x30    // Vector3 position
#define OFF_ENTITY_TEAM     0xD8    // ShowEntity -> m_EntityCampType
#define OFF_HEALTH          0x1AC   // ShowEntity -> m_Hp
#define OFF_MAX_HEALTH      0x1B0   // ShowEntity -> m_HpMax
#define OFF_HERO_NAME       0x918   // ShowPlayer -> m_HeroName
#define OFF_RANK_LEVEL      0x954   // ShowPlayer -> m_uiRankLevel
#define OFF_SKIN_ID         0x8FC   // ShowPlayer -> m_iOriginSkinId
#define OFF_ENTITY_STATE    0x210   // Action state (int)

// Skill Offsets (Placeholder - highly dynamic)
#define OFF_SKILL_COMP      0x110   // ShowEntity -> m_OwnSkillComp
#define OFF_SKILL_ARRAY     0x48    // SkillComponent -> m_NormalSkill
#define OFF_SKILL_CD        0x60    // OwnSkillData -> m_startStageTime (approx)

// RVAs for Hooks (Verified from dump.cs)
#define RVA_GET_SKILL_CD    0x66E4A64 
#define RVA_GET_CUR_CD      0x67BD63C // ShowCoolDownComp.GetCurCD
#define RVA_REVEAL_MAP      0x4FB2878 // ShowPlayer.SetFowRevealerRange
#define RVA_GET_SKIN        0x694752  // ShowPlayer.m_iOriginSkinId (offset)
#define RVA_CAMERA_DIST     0x9AA10   
#define OFF_SUMMON_SKILL_ID 0x9A4     // ShowPlayer -> m_iSummonSkillId

// Security
#define OFF_PH1_AUTH        0x23a58

static uintptr_t g_unityBase = 0, g_ph1Base = 0;

// Global States
static _Atomic BOOL g_esp = true;
static _Atomic BOOL g_espBox = true;
static _Atomic BOOL g_snapLine = false;
static _Atomic BOOL g_heroName = true;
static _Atomic BOOL g_hpBar = true;
static _Atomic BOOL g_espJungle = false; // Lord & Turtle
static _Atomic BOOL g_espCreep = false;  // Buff & Small Creeps
static _Atomic BOOL g_skillCD = false;
static _Atomic BOOL g_spellCD = false;
static _Atomic BOOL g_mapHack = false;
static _Atomic float g_droneView = 15.0f;
static _Atomic BOOL g_range = false;

// Special Mods
static _Atomic BOOL g_kimmyAuto = false;
static _Atomic BOOL g_mageSkill = false;
static _Atomic BOOL g_autoTap = false;
static _Atomic BOOL g_autoAim = false; 
static _Atomic BOOL g_rankInfo = false;
static _Atomic BOOL g_skinHack = false;
static _Atomic BOOL g_safeMode = false;

static UITextView *g_logView = nil;

typedef struct { float x, y, z; } Vector3;
typedef struct { float x, y; } Vector2;

// --- HELPERS ---
uintptr_t get_base(const char *name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *imgName = _dyld_get_image_name(i);
        if (imgName && strstr(imgName, name)) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

void add_log(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            NSDateFormatter *df = [[NSDateFormatter alloc] init];
            [df setDateFormat:@"HH:mm:ss"];
            NSString *time = [df stringFromDate:[NSDate date]];
            g_logView.text = [g_logView.text stringByAppendingFormat:@"\n[%@] %@", time, msg];
            [g_logView scrollRangeToVisible:NSMakeRange(g_logView.text.length, 0)];
        }
    });
}

// --- UNITY STRING HELPER ---
NSString* read_unity_string(uintptr_t ptr) {
    if (!ptr || ptr < 0x100000) return @"Unknown";
    int len = *(int*)(ptr + 0x10);
    if (len <= 0 || len > 100) return @"Unknown";
    uint16_t *chars = (uint16_t*)(ptr + 0x14);
    return [NSString stringWithCharacters:chars length:len];
}

// --- ESP OVERLAY ---
@interface ESPOverlay : UIView
+ (instancetype)shared;
@end

@implementation ESPOverlay
+ (instancetype)shared {
    static ESPOverlay *i = nil; static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [[self alloc] initWithFrame:[UIScreen mainScreen].bounds]; });
    return i;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateESP)];
        [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    }
    return self;
}

- (void)updateESP { if (atomic_load(&g_esp)) [self setNeedsDisplay]; }

// Helper methods (Implementasi placeholder)
- (float)getHeroHpPercent:(void*)player {
    if (!player) return 0.0f;
    int hp = *(int*)((uintptr_t)player + OFF_HEALTH);
    int maxHp = *(int*)((uintptr_t)player + OFF_MAX_HEALTH);
    if (maxHp <= 0) return 0.0f;
    float p = (float)hp / (float)maxHp;
    return (p > 1.0f) ? 1.0f : (p < 0.0f ? 0.0f : p);
}

- (NSString*)getHeroName:(void*)player {
    if (!player) return @"Unknown";
    uintptr_t namePtr = *(uintptr_t*)((uintptr_t)player + OFF_HERO_NAME);
    return read_unity_string(namePtr);
}

- (float)getDistanceToPlayer:(Vector3)enemyPos {
    void* (*get_bm)() = (void*(*)())(g_unityBase + RVA_GET_BM);
    void* bm = get_bm();
    if (!bm) return 0.0f;
    void* local = *(void**)((uintptr_t)bm + OFF_BM_LOCAL_PLAYER);
    if (!local) return 0.0f;
    Vector3 myPos = *(Vector3*)((uintptr_t)local + OFF_ENTITY_POS);
    float dx = enemyPos.x - myPos.x;
    float dy = enemyPos.y - myPos.y;
    float dz = enemyPos.z - myPos.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}

- (float)getSkillCooldown:(void*)player slot:(int)slot {
    if (!player) return 0;
    uintptr_t skillComp = *(uintptr_t*)((uintptr_t)player + OFF_SKILL_COMP);
    if (!skillComp) return 0;
    uintptr_t skillArray = *(uintptr_t*)(skillComp + OFF_SKILL_ARRAY);
    if (!skillArray) return 0;
    uintptr_t skill = *(uintptr_t*)(skillArray + 0x20 + (slot * 8));
    if (!skill) return 0;
    return *(float*)(skill + OFF_SKILL_CD);
}

- (float)getSkillCooldown:(void*)player withID:(int)skillID {
    if (!player || skillID <= 0 || !g_unityBase) return 0;
    
    // player -> m_ShowCoolDownComp (0x100)
    void* cdComp = *(void**)((uintptr_t)player + 0x100);
    if (!cdComp) return 0;

    // Call: uint GetCurCD(int spellID, bool checkShare)
    uint32_t (*get_cd)(void*, int, bool) = (uint32_t(*)(void*, int, bool))(g_unityBase + RVA_GET_CUR_CD);
    uint32_t cdMs = get_cd(cdComp, skillID, false);
    
    return (float)cdMs / 1000.0f; // Convert ms to seconds
}

- (void)drawRect:(CGRect)rect {
    if (!atomic_load(&g_esp) || !g_unityBase) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    float scale = [UIScreen mainScreen].scale;
    float screenW = rect.size.width;
    float screenH = rect.size.height;

    void* (*get_bm)() = (void*(*)())(g_unityBase + RVA_GET_BM);
    void* bm = get_bm(); if (!bm) return;

    void* playerList = *(void**)((uintptr_t)bm + OFF_BM_PLAYER_LIST);
    if (!playerList || (uintptr_t)playerList < 0x100000) return;

    void* items = *(void**)((uintptr_t)playerList + 0x10);
    int size = *(int*)((uintptr_t)playerList + 0x18);
    if (!items || size <= 0) return;

    void* (*get_main)() = (void*(*)())(g_unityBase + RVA_CAMERA_MAIN);
    void* mainCam = get_main(); if (!mainCam) return;
    Vector3 (*w2s)(void*, Vector3) = (Vector3(*)(void*, Vector3))(g_unityBase + RVA_W2S);

    for (int i = 0; i < size; i++) {
        void* player = *(void**)((uintptr_t)items + 0x20 + (i * 8));
        if (!player || (uintptr_t)player < 0x100000) continue;

        Vector3 enemyPos = *(Vector3*)((uintptr_t)player + OFF_ENTITY_POS);
        Vector3 screenPos = w2s(mainCam, enemyPos);
        
        if (screenPos.z > 0) {
            int team = *(int*)((uintptr_t)player + OFF_ENTITY_TEAM);
            void* local = *(void**)((uintptr_t)bm + OFF_BM_LOCAL_PLAYER);
            int myTeam = local ? *(int*)((uintptr_t)local + OFF_ENTITY_TEAM) : 0;
            
            // Logika Identifikasi Tipe Entity
            NSString *heroName = [self getHeroName:player];
            BOOL isHero = YES;
            BOOL isBoss = [heroName containsString:@"Lord"] || [heroName containsString:@"Turtle"];
            BOOL isJungle = [heroName containsString:@"Monster"] || [heroName containsString:@"Buff"] || [heroName containsString:@"Creep"];
            
            if (isBoss || isJungle) isHero = NO;

            // FILTER: Fokus Enemy (Default)
            if (isHero) {
                if (team == myTeam && !atomic_load(&g_mapHack)) continue;
            } else if (isBoss) {
                if (!atomic_load(&g_espJungle)) continue;
            } else if (isJungle) {
                if (!atomic_load(&g_espCreep)) continue;
            }

            // FIX: Posisi dengan Retina Scaling
            float x = screenPos.x / scale;
            float y = screenH - (screenPos.y / scale);
            
            float boxWidth = (700.0f / screenPos.z) / scale; 
            float boxHeight = boxWidth * 1.5f;
            
            // Penentuan Warna Berdasarkan Tipe
            UIColor *drawColor = [UIColor redColor]; // Default Enemy
            if (isHero && team == myTeam) drawColor = [UIColor greenColor];
            else if (isBoss) drawColor = [UIColor purpleColor];
            else if (isJungle) drawColor = [UIColor yellowColor];

            // 1. Gambar BOX
            if (atomic_load(&g_espBox)) {
                CGContextSetStrokeColorWithColor(ctx, drawColor.CGColor);
                CGContextSetLineWidth(ctx, 1.2);
                CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight, boxWidth, boxHeight));
            }

            // 2. Gambar SNAP LINE
            if (atomic_load(&g_snapLine) && isHero) {
                CGContextSetStrokeColorWithColor(ctx, [drawColor colorWithAlphaComponent:0.5].CGColor);
                CGContextSetLineWidth(ctx, 1.0);
                CGContextMoveToPoint(ctx, screenW / 2, screenH);
                CGContextAddLineToPoint(ctx, x, y);
                CGContextStrokePath(ctx);
            }
            
            // 3. Gambar HP BAR
            if (atomic_load(&g_hpBar)) {
                float hpPercent = [self getHeroHpPercent:player];
                CGContextSetFillColorWithColor(ctx, [UIColor darkGrayColor].CGColor);
                CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 8, boxWidth, 4));
                CGContextSetFillColorWithColor(ctx, drawColor.CGColor);
                CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 8, boxWidth * hpPercent, 4));
            }
            
            // 4. Gambar INFO
            float distance = [self getDistanceToPlayer:enemyPos];
            
            // Rank Info Logic
            NSString *rankStr = @"";
            if (atomic_load(&g_rankInfo)) {
                uint32_t rankLvl = *(uint32_t*)((uintptr_t)player + OFF_RANK_LEVEL);
                if (rankLvl >= 7) rankStr = @"[Mythic] ";
                else if (rankLvl >= 6) rankStr = @"[Legend] ";
                else rankStr = @"[Epic] ";
            }

            NSString *info = [NSString stringWithFormat:@"%@%@ (%.0fm)", rankStr, heroName, distance];
            NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:9 weight:UIFontWeightBold], 
                                  NSForegroundColorAttributeName: [UIColor whiteColor]};
            [info drawAtPoint:CGPointMake(x - boxWidth/2, y - boxHeight - 20) withAttributes:attrs];

                // 5. Draw Skill CD ESP
                if (atomic_load(&g_skillCD) && isHero) {
                    float s1 = [self getSkillCooldown:player slot:0];
                    float s2 = [self getSkillCooldown:player slot:1];
                    float s3 = [self getSkillCooldown:player slot:2]; // Ult
                    
                    // Battle Spell CD
                    float spellCD = 0;
                    if (atomic_load(&g_spellCD)) {
                        int spellID = *(int*)((uintptr_t)player + OFF_SUMMON_SKILL_ID);
                        spellCD = [self getSkillCooldown:player withID:spellID];
                    }

                    NSString *cdText = [NSString stringWithFormat:@"S1:%@ | S2:%@ | ULT:%@%@", 
                                       (s1 > 0 ? [NSString stringWithFormat:@"%.1fs", s1] : @"READY"),
                                       (s2 > 0 ? [NSString stringWithFormat:@"%.1fs", s2] : @"READY"),
                                       (s3 > 0 ? [NSString stringWithFormat:@"%.1fs", s3] : @"READY"),
                                       (spellCD > 0 ? [NSString stringWithFormat:@" | SP:%.1fs", spellCD] : @"")];
                    
                    NSDictionary *cdAttrs = @{NSFontAttributeName: [UIFont systemFontOfSize:7], 
                                            NSForegroundColorAttributeName: [UIColor cyanColor]};
                    [cdText drawAtPoint:CGPointMake(x - boxWidth/2, y + 5) withAttributes:cdAttrs];
                }
        }
    }
}
@end

// --- PREMIUM MENU ---
@interface PH1Menu : UIView
@property (nonatomic, assign) CGPoint startPos;
@property (nonatomic, strong) UIView *sidebar;
@property (nonatomic, strong) UIView *contentArea;
@property (nonatomic, strong) NSMutableArray *tabViews;
@end

@implementation PH1Menu
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.08 alpha:0.95];
        self.layer.cornerRadius = 12;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
        self.hidden = YES;
        
        [self setupLayout];
    }
    return self;
}

- (void)setupLayout {
    // Sidebar
    self.sidebar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, self.frame.size.height)];
    self.sidebar.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:1.0];
    [self addSubview:self.sidebar];
    
    UILabel *logo = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 100, 40)];
    logo.text = @"SKECH"; logo.textColor = [UIColor redColor];
    logo.textAlignment = NSTextAlignmentCenter; logo.font = [UIFont systemFontOfSize:18 weight:UIFontWeightHeavy];
    [self.sidebar addSubview:logo];
    
    // Content Area
    self.contentArea = [[UIView alloc] initWithFrame:CGRectMake(110, 10, self.frame.size.width - 120, self.frame.size.height - 20)];
    [self addSubview:self.contentArea];
    
    NSArray *tabs = @[@"Visuals", @"Combat", @"Special", @"Misc"];
    for (int i = 0; i < tabs.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(0, 60 + (i * 45), 100, 35);
        [btn setTitle:tabs[i] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        btn.tag = i;
        [btn addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventTouchUpInside];
        [self.sidebar addSubview:btn];
    }
    
    [self tabChanged:nil]; // Load first tab
}

- (void)tabChanged:(UIButton *)sender {
    int tag = sender ? (int)sender.tag : 0;
    for (UIView *v in self.contentArea.subviews) [v removeFromSuperview];
    
    int y = 0;
    if (tag == 0) { // Visuals
        [self addSection:@"Visuals" y:&y];
        [self addToggle:@"Master ESP" y:&y state:&g_esp];
        [self addToggle:@"Box ESP" y:&y state:&g_espBox];
        [self addToggle:@"Hero Info" y:&y state:&g_heroName];
        [self addToggle:@"Rank Info" y:&y state:&g_rankInfo];
        [self addToggle:@"Jungle (Lord/Turtle)" y:&y state:&g_espJungle];
        [self addToggle:@"Creep ESP" y:&y state:&g_espCreep];
    } else if (tag == 1) { // Combat
        [self addSection:@"Combat Mods" y:&y];
        [self addToggle:@"Auto Aim (Franco/Selena)" y:&y state:&g_autoAim];
        [self addToggle:@"Infinite Range" y:&y state:&g_range];
        [self addSlider:@"Drone View" y:&y state:&g_droneView min:15 max:100];
    } else if (tag == 2) { // Special
        [self addSection:@"Hero Specific" y:&y];
        [self addToggle:@"Kimmy Auto Lock" y:&y state:&g_kimmyAuto];
        [self addToggle:@"Mage Skill Range" y:&y state:&g_mageSkill];
        [self addToggle:@"Visual Skin Hack" y:&y state:&g_skinHack];
        [self addToggle:@"Auto Tap Skills" y:&y state:&g_autoTap];
    } else { // Misc
        [self addSection:@"Miscellaneous" y:&y];
        [self addToggle:@"Map Hack" y:&y state:&g_mapHack];
        [self addToggle:@"SAFE MODE (Bypass Detect)" y:&y state:&g_safeMode];
        
        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(0, y, self.contentArea.frame.size.width, 100)];
        g_logView.backgroundColor = [UIColor blackColor];
        g_logView.textColor = [UIColor greenColor];
        g_logView.font = [UIFont fontWithName:@"Courier" size:10];
        g_logView.editable = NO;
        [self.contentArea addSubview:g_logView];
    }
}

- (void)addSection:(NSString *)title y:(int *)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, *y, self.contentArea.frame.size.width, 20)];
    l.text = [title uppercaseString]; l.textColor = [UIColor redColor];
    l.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [self.contentArea addSubview:l];
    *y += 25;
}

- (void)addToggle:(NSString *)text y:(int *)y state:(_Atomic BOOL *)state {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, *y, self.contentArea.frame.size.width, 35)];
    card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
    card.layer.cornerRadius = 4;
    [self.contentArea addSubview:card];
    
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 150, 35)];
    l.text = text; l.textColor = [UIColor whiteColor]; l.font = [UIFont systemFontOfSize:11];
    [card addSubview:l];
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(card.frame.size.width - 55, 2, 40, 30)];
    sw.transform = CGAffineTransformMakeScale(0.7, 0.7);
    sw.on = atomic_load(state);
    sw.onTintColor = [UIColor redColor];
    objc_setAssociatedObject(sw, "state_ptr", [NSValue valueWithPointer:state], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];
    *y += 40;
}

- (void)addSlider:(NSString *)text y:(int *)y state:(_Atomic float *)state min:(float)min max:(float)max {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, *y, 150, 15)];
    l.text = text; l.textColor = [UIColor lightGrayColor]; l.font = [UIFont systemFontOfSize:9];
    [self.contentArea addSubview:l];
    
    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, *y + 15, self.contentArea.frame.size.width, 20)];
    sl.minimumValue = min; sl.maximumValue = max; sl.value = atomic_load(state);
    sl.minimumTrackTintColor = [UIColor redColor];
    objc_setAssociatedObject(sl, "state_ptr", [NSValue valueWithPointer:state], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sl addTarget:self action:@selector(onSlider:) forControlEvents:UIControlEventValueChanged];
    [self.contentArea addSubview:sl];
    *y += 45;
}

- (void)onSwitch:(UISwitch *)sw {
    _Atomic BOOL *state = [objc_getAssociatedObject(sw, "state_ptr") pointerValue];
    atomic_store(state, sw.on);
    
    // SAFE MODE Logic
    if (state == &g_safeMode && sw.on) {
        atomic_store(&g_range, false);
        atomic_store(&g_skinHack, false);
        add_log(@"SAFE MODE: High-risk mods disabled.");
        [self tabChanged:nil]; // Refresh UI
    }
    
    add_log([NSString stringWithFormat:@"Toggle: %@", sw.on ? @"ON" : @"OFF"]);
}

- (void)onSlider:(UISlider *)sl {
    _Atomic float *state = [objc_getAssociatedObject(sl, "state_ptr") pointerValue];
    atomic_store(state, sl.value);
}

- (void)toggleMenu { self.hidden = !self.hidden; }
- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e { self.startPos = [[t anyObject] locationInView:self]; }
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint loc = [[t anyObject] locationInView:self.superview];
    self.center = CGPointMake(loc.x - self.startPos.x + self.bounds.size.width/2, loc.y - self.startPos.y + self.bounds.size.height/2);
}
@end

// --- HOOKS & IMPLEMENTATION ---
float (*old_R)(void *i);
float new_R(void *i) { 
    if(!i || (uintptr_t)i < 0x100000) return old_R(i); 
    return atomic_load(&g_range) ? 999.0f : old_R(i); 
}

// Drone View Updater (Timer based)
static dispatch_source_t droneTimer = nil;
static float lastDroneVal = 0;

void update_drone_view() {
    if (droneTimer) return; // Already running
    
    droneTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, 
                                      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(droneTimer, DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(droneTimer, ^{
        if (g_unityBase && g_unityBase > 0x100000) {
            float val = atomic_load(&g_droneView);
            if (val > 15.0f) {
                uintptr_t addr = g_unityBase + RVA_CAMERA_DIST;
                if (addr > 0x100000) {
                    vm_protect(mach_task_self(), addr, 4, false, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
                    memcpy((void*)addr, &val, 4);
                    
                    if (val != lastDroneVal) {
                        add_log([NSString stringWithFormat:@"Drone View: %.0f", val]);
                        lastDroneVal = val;
                    }
                }
            }
        }
    });
    dispatch_resume(droneTimer);
}

// --- DEVELOPMENT HOOKS (PLANNED) ---
int (*old_GetSkin)(void *player);
int new_GetSkin(void *player) {
    if (atomic_load(&g_skinHack)) return 1; // Default skin 1 (or custom logic)
    return old_GetSkin(player);
}

void (*old_Map)(void *player, float inner, float outer);
void new_Map(void *player, float inner, float outer) {
    if (atomic_load(&g_mapHack)) {
        inner = 1000.0f; 
        outer = 1000.0f;
    }
    old_Map(player, inner, outer);
}

__attribute__((constructor))
static void initialize() {
    // Basic anti-debug bypass
    syscall(SYS_ptrace, 31, 0, 0, 0); 
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_unityBase = get_base(UNITY_NAME);
        
        // Load external dylib if exists
        NSString *path = [[NSBundle mainBundle] pathForResource:@"ph1mlbb" ofType:@"dylib"];
        if (path) {
            dlopen([path UTF8String], RTLD_NOW);
            g_ph1Base = get_base(PH1_DYLIB_NAME);
        }

        // Patch auth if base found
        if (g_ph1Base) {
            unsigned char p[] = { 0x20, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6 };
            if (vm_protect(mach_task_self(), g_ph1Base + OFF_PH1_AUTH, 8, false, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY) == KERN_SUCCESS) {
                memcpy((void *)(g_ph1Base + OFF_PH1_AUTH), p, 8);
                add_log(@"System: Security Bypass Success.");
            }
        }

        if (g_unityBase) {
            // Hook Attack Range
            MSHookFunction((void *)(g_unityBase + RVA_GET_ATK_DIS), (void *)new_R, (void **)&old_R);
            
            // Map Hack Hook (Verified RVA)
            MSHookFunction((void *)(g_unityBase + RVA_REVEAL_MAP), (void *)new_Map, (void **)&old_Map);
            
            // Future Development Hooks (Placeholders)
            // MSHookFunction((void *)(g_unityBase + RVA_GET_SKIN), (void *)new_GetSkin, (void **)&old_GetSkin);

            // Start Drone View Patcher
            update_drone_view();
            
            UIWindow *win = [UIApplication sharedApplication].keyWindow;
            if (!win) win = [[UIApplication sharedApplication] windows].firstObject;

            // Add ESP Overlay
            [win addSubview:[ESPOverlay shared]];
            
            // Add Premium Menu
            PH1Menu *menu = [[PH1Menu alloc] initWithFrame:CGRectMake(40, 100, 320, 460)];
            [win addSubview:menu];
            
            // Add Floating Icon (pH-1)
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(20, 150, 60, 60);
            btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:0.8];
            btn.layer.cornerRadius = 30;
            btn.layer.shadowColor = [UIColor cyanColor].CGColor;
            btn.layer.shadowOpacity = 0.8;
            btn.layer.shadowRadius = 10;
            [btn setTitle:@"pH-1" forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
            [btn addTarget:menu action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
            [win addSubview:btn];
            
            add_log(@"System: All modules loaded.");
        } else {
            // add_log(@"System: UnityFramework not found!");
        }
    });
}
