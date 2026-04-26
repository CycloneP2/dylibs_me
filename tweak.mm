#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ========== OFFSETS DARI EDGYMYLBB.DYLIB ==========
#define EDGY_NAME "edgymlbb.dylib"
#define OFF_AUTH_BYPASS     0x23a58   // Fungsi cek lisensi
#define OFF_AC_NEUTRALIZE   0x5004    // Fungsi anti-cheat
#define OFF_BATTLE_CONTROL  0x5328    // Fungsi battle hacks
#define OFF_RETRI_ZONE_X    0xC7788   // Data konstanta Retri

// ========== VARIABLE GLOBAL ==========
static uintptr_t g_edgyBase = 0;
static BOOL g_espEnabled = NO, g_snaplines = NO, g_dnsBypass = NO;

// ========== MEMORY HELPER ==========
void safe_write(uintptr_t addr, void *data, size_t size) {
    if (!addr) return;
    vm_protect(mach_task_self(), (vm_address_t)addr, size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    memcpy((void *)addr, data, size);
    vm_protect(mach_task_self(), (vm_address_t)addr, size, false, VM_PROT_READ | VM_PROT_EXECUTE);
}

uintptr_t get_base(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *img = _dyld_get_image_name(i);
        if (img && strstr(img, name)) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

// ========== ESP OVERLAY ENGINE ==========
@interface ESPView : UIView
+ (instancetype)shared;
@end

@implementation ESPView
+ (instancetype)shared {
    static ESPView *i = nil; static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [[self alloc] initWithFrame:[UIScreen mainScreen].bounds]; });
    return i;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { self.userInteractionEnabled = NO; self.backgroundColor = [UIColor clearColor]; }
    return self;
}
- (void)drawRect:(CGRect)rect {
    if (!g_espEnabled) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor cyanColor] setStroke];
    if (g_snaplines) {
        CGContextMoveToPoint(ctx, rect.size.width/2, rect.size.height);
        CGContextAddLineToPoint(ctx, rect.size.width/2, rect.size.height/2); 
        CGContextStrokePath(ctx);
    }
}
@end

// ========== MODERN MOD MENU UI ==========
@interface ModernMenu : UIView
@property (nonatomic, assign) CGPoint startPos;
@end

@implementation ModernMenu
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 25; self.clipsToBounds = YES;
        self.layer.borderWidth = 1.5; self.layer.borderColor = [UIColor cyanColor].CGColor;
        
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        blur.frame = self.bounds; [self addSubview:blur];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, frame.size.width, 30)];
        title.text = @"🔥 EDGY ULTIMATE 🔥"; title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter; title.font = [UIFont boldSystemFontOfSize:20];
        [self addSubview:title];

        [self setupControls];
    }
    return self;
}

- (void)setupControls {
    int y = 70;
    [self addToggle:@"ANTIPATCH (AC)" y:y action:@selector(toggleAC:)]; y += 50;
    [self addToggle:@"ENABLE ESP" y:y action:@selector(toggleESP:)]; y += 50;
    [self addToggle:@"SNAPLINES" y:y action:@selector(toggleSnap:)]; y += 50;
    [self addToggle:@"BATTLE CONTROL" y:y action:@selector(toggleBattle:)]; y += 50;
    
    UILabel *foot = [[UILabel alloc] initWithFrame:CGRectMake(0, self.frame.size.height-30, self.frame.size.width, 20)];
    foot.text = @"Licensed to: BYPASS_ACTIVE"; foot.textColor = [UIColor cyanColor];
    foot.font = [UIFont systemFontOfSize:10]; foot.textAlignment = NSTextAlignmentCenter;
    [self addSubview:foot];
}

- (void)addToggle:(NSString *)text y:(int)y action:(SEL)sel {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(30, y, 150, 30)];
    l.text = text; l.textColor = [UIColor lightGrayColor]; [self addSubview:l];
    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(220, y, 50, 30)];
    s.onTintColor = [UIColor cyanColor]; [s addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [self addSubview:s];
}

// Actions Terhubung ke Internal Edgy
- (void)toggleAC:(UISwitch *)s {
    void (*func)(bool) = (void(*)(bool))(g_edgyBase + OFF_AC_NEUTRALIZE);
    if (func) func(s.on);
}

- (void)toggleBattle:(UISwitch *)s {
    void (*func)() = (void(*)())(g_edgyBase + OFF_BATTLE_CONTROL);
    if (func && s.on) func();
}

- (void)toggleESP:(UISwitch *)s { g_espEnabled = s.on; [[ESPView shared] setNeedsDisplay]; }
- (void)toggleSnap:(UISwitch *)s { g_snaplines = s.on; [[ESPView shared] setNeedsDisplay]; }

// Logic Drag
- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e { self.startPos = [[t anyObject] locationInView:self]; }
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint loc = [[t anyObject] locationInView:self.superview];
    self.center = CGPointMake(loc.x - self.startPos.x + self.bounds.size.width/2, loc.y - self.startPos.y + self.bounds.size.height/2);
}
@end

// ========== BOOTSTRAP ==========
__attribute__((constructor))
static void initialize() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        dlopen(EDGY_NAME, RTLD_NOW);
        g_edgyBase = get_base(EDGY_NAME);
        
        if (g_edgyBase) {
            // 1. BYPASS LISENSI (Koreksi Poin 5 & 8)
            // Mengganti fungsi Auth agar selalu mengembalikan nilai TRUE (Sukses)
            uintptr_t authAddr = g_edgyBase + OFF_AUTH_BYPASS;
            unsigned char patch[] = { 0x20, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6 }; // MOV X0, #1; RET
            safe_write(authAddr, patch, 8);
            
            // 2. SETUP UI
            UIWindow *win = [UIApplication sharedApplication].keyWindow;
            [win addSubview:[ESPView shared]];
            
            ModernMenu *menu = [[ModernMenu alloc] initWithFrame:CGRectMake(60, 150, 310, 320)];
            menu.hidden = YES; // Sembunyikan dulu
            [win addSubview:menu];
            
            // 3. Tombol Floating untuk Show/Hide
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(20, 150, 50, 50);
            btn.backgroundColor = [[UIColor cyanColor] colorWithAlphaComponent:0.8];
            btn.layer.cornerRadius = 25;
            [btn setTitle:@"EDGY" forState:UIControlStateNormal];
            [btn addTarget:menu action:@selector(setHidden:) forControlEvents:UIControlEventTouchDown]; // Sederhana
            [win addSubview:btn];
            
            NSLog(@"[SUCCESS] Edgy Ultimate Injected & Bypassed!");
        }
    });
}
