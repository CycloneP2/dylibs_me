#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <sys/syscall.h>
#import <mach/mach.h>

#define PH1_DYLIB_NAME      "ph1mlbb.dylib"
#define UNITY_NAME          "UnityFramework"
#define RVA_CAMERA_MAIN     0x89FF130
#define RVA_W2S             0x89FE040
#define RVA_GET_BM          0x6A48A98 
#define RVA_GET_ATK_DIS     0x4FEC06C
#define OFF_BM_PLAYER_LIST  0x78
#define OFF_ENTITY_POS      0x30
#define OFF_PH1_AUTH        0x23a58

static uintptr_t g_unityBase = 0, g_ph1Base = 0;
static _Atomic BOOL g_esp = false, g_range = false;
static UITextView *g_logView = nil;

struct Vector3 { float x, y, z; };

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
            g_logView.text = [g_logView.text stringByAppendingFormat:@"\n> %@", msg];
            [g_logView scrollRangeToVisible:NSMakeRange(g_logView.text.length, 0)];
        }
    });
}

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
        self.userInteractionEnabled = NO; self.backgroundColor = [UIColor clearColor];
        CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateESP)];
        [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            [self removeFromSuperview];
        }];
    }
    return self;
}
- (void)updateESP { if (atomic_load(&g_esp)) [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    if (!atomic_load(&g_esp) || !g_unityBase) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    void* (*get_bm)() = (void*(*)())(g_unityBase + RVA_GET_BM);
    void* bm = get_bm(); if (!bm) return;

    void* playerList = *(void**)((uintptr_t)bm + OFF_BM_PLAYER_LIST);
    if (!playerList || (uintptr_t)playerList < 0x100000) return;

    void* items = *(void**)((uintptr_t)playerList + 0x10);
    int size = *(int*)((uintptr_t)playerList + 0x18);
    // ✅ FIX POIN 1: Validasi items sebelum loop
    if (!items || (uintptr_t)items < 0x100000 || size <= 0) return;

    void* (*get_main)() = (void*(*)())(g_unityBase + RVA_CAMERA_MAIN);
    void* mainCam = get_main(); if (!mainCam) return;
    Vector3 (*w2s)(void*, Vector3) = (Vector3(*)(void*, Vector3))(g_unityBase + RVA_W2S);

    for (int i = 0; i < size; i++) {
        void* player = *(void**)((uintptr_t)items + 0x20 + (i * 8));
        if (!player || (uintptr_t)player < 0x100000) continue;

        Vector3 enemyPos = *(Vector3*)((uintptr_t)player + OFF_ENTITY_POS);
        Vector3 screenPos = w2s(mainCam, enemyPos);
        
        if (screenPos.z > 0) {
            float x = screenPos.x;
            float y = rect.size.height - screenPos.y;
            CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
            CGContextSetLineWidth(ctx, 1.5);
            CGContextMoveToPoint(ctx, rect.size.width/2, rect.size.height);
            CGContextAddLineToPoint(ctx, x, y);
            CGContextStrokePath(ctx);
        }
    }
}
@end

@interface PH1Menu : UIView
@property (nonatomic, assign) CGPoint startPos;
@end

@implementation PH1Menu
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 20; self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        self.hidden = YES;
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, frame.size.width, 25)];
        title.text = @"🌟 pH-1 PRO 🌟"; title.textColor = [UIColor cyanColor];
        title.textAlignment = NSTextAlignmentCenter; [self addSubview:title];

        g_logView = [[UITextView alloc] initWithFrame:CGRectMake(10, 180, frame.size.width - 20, 120)];
        g_logView.backgroundColor = [UIColor blackColor];
        g_logView.textColor = [UIColor greenColor]; g_logView.editable = NO;
        g_logView.text = @"[READY] pH-1 PRO ACTIVE";
        [self addSubview:g_logView];

        [self setupControls];
    }
    return self;
}

- (void)setupControls {
    int y = 50;
    UISwitch *s1 = [[UISwitch alloc] initWithFrame:CGRectMake(230, y, 50, 30)];
    [s1 addTarget:self action:@selector(toggleESP:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:s1];
    UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 150, 30)];
    l1.text = @"ESP PLAYER"; l1.textColor = [UIColor whiteColor]; [self addSubview:l1];
    
    y += 50;
    UISwitch *s2 = [[UISwitch alloc] initWithFrame:CGRectMake(230, y, 50, 30)];
    [s2 addTarget:self action:@selector(toggleRange:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:s2];
    UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 150, 30)];
    l2.text = @"INFINITE RANGE"; l2.textColor = [UIColor whiteColor]; [self addSubview:l2];

    // ✅ FIX POIN 2: Tombol Close (X)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(self.frame.size.width - 40, 5, 30, 30);
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:closeBtn];
}

- (void)toggleMenu { self.hidden = !self.hidden; }
- (void)toggleESP:(UISwitch *)s { atomic_store(&g_esp, s.on); add_log(s.on ? @"ESP ON" : @"ESP OFF"); }
- (void)toggleRange:(UISwitch *)s { atomic_store(&g_range, s.on); add_log(s.on ? @"Range ON" : @"Range OFF"); }

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e { self.startPos = [[t anyObject] locationInView:self]; }
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint loc = [[t anyObject] locationInView:self.superview];
    self.center = CGPointMake(loc.x - self.startPos.x + self.bounds.size.width/2, loc.y - self.startPos.y + self.bounds.size.height/2);
}
@end

float (*old_R)(void *i);
float new_R(void *i) { if(!i || (uintptr_t)i < 0x100000) return old_R(i); return atomic_load(&g_range) ? 999.0f : old_R(i); }

__attribute__((constructor))
static void initialize() {
    syscall(SYS_ptrace, 31, 0, 0, 0); 
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_unityBase = get_base(UNITY_NAME);
        
        NSString *path = [[NSBundle mainBundle] pathForResource:@"ph1mlbb" ofType:@"dylib"];
        if (path) {
            dlopen([path UTF8String], RTLD_NOW);
            g_ph1Base = get_base(PH1_DYLIB_NAME);
        }

        if (g_ph1Base) {
            unsigned char p[] = { 0x20, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6 };
            if (vm_protect(mach_task_self(), g_ph1Base + OFF_PH1_AUTH, 8, false, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY) == KERN_SUCCESS) {
                memcpy((void *)(g_ph1Base + OFF_PH1_AUTH), p, 8);
                add_log(@"pH-1 Auth Bypassed.");
            }
        }

        if (g_unityBase) {
            MSHookFunction((void *)(g_unityBase + RVA_GET_ATK_DIS), (void *)new_R, (void **)&old_R);
            UIWindow *win = [UIApplication sharedApplication].keyWindow;
            [win addSubview:[ESPOverlay shared]];
            PH1Menu *menu = [[PH1Menu alloc] initWithFrame:CGRectMake(40, 100, 300, 320)];
            [win addSubview:menu];
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(10, 100, 50, 50); btn.backgroundColor = [UIColor cyanColor];
            btn.layer.cornerRadius = 25; [btn setTitle:@"pH-1" forState:UIControlStateNormal];
            [btn addTarget:menu action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
            [win addSubview:btn];
            add_log(@"pH-1 System Ready.");
        }
    });
}
