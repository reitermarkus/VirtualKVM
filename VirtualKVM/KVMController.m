#import "KVMController.h"
#import "KVMBluetoothController.h"
#import "GVUserDefaults+KVMApp.h"
#import "KVMStatusItem.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <ServiceManagement/ServiceManagement.h>
#include <sys/types.h>
#include <sys/sysctl.h>

@interface KVMController ()

@property (nonatomic, strong) KVMThunderboltObserver *thunderboltObserver;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic) IOPMAssertionID sleepAssertion;
@property (nonatomic) BOOL isClient;

@property (nonatomic) IBOutlet NSMenu *menu;
@property (weak) IBOutlet NSMenuItem *toggleBluetoothMenuItem;
@property (weak) IBOutlet NSMenuItem *toggleDisplayMenuItem;
@property (weak) IBOutlet NSMenuItem *toggleSleepMenuItem;
@property (weak) IBOutlet NSMenuItem *toggleLaunchAtLoginMenuItem;
@property (weak) IBOutlet NSMenuItem *connectionStatusMenuItem;
@property (nonatomic, assign) CFStringRef assertionType;

@end

@implementation KVMController

+ (NSString *)machineModel {
  size_t len = 0;
  sysctlbyname("hw.model", NULL, &len, NULL, 0);

  if (len) {
    char *model = malloc(len * sizeof(char));
    sysctlbyname("hw.model", model, &len, NULL, 0);
    NSString *model_ns = [NSString stringWithUTF8String:model];
    free(model);
    NSLog(NSLocalizedString(@"Running on %@.", comment:nil), model_ns);
    return model_ns;
  }

  return @"Unknown";
}

- (id)init {
  self = [super init];
  self.isClient = [[KVMController machineModel] rangeOfString:@"iMac"].location == NSNotFound;

  if (!self.isClient) {
    self.thunderboltObserver = [[KVMThunderboltObserver alloc] initWithDelegate:self];
    [self.thunderboltObserver startObserving];
  }


  return self;
}

- (NSString *)modeString {
  if (self.isClient) {
    return NSLocalizedString(@"Client Mode", comment:nil);
  } else {
    return NSLocalizedString(@"Host Mode", comment:nil);
  }
}

- (void)awakeFromNib {
  self.menu.autoenablesItems = NO;
  self.toggleBluetoothMenuItem.state = [GVUserDefaults standardUserDefaults].toggleBluetooth ? NSOnState : NSOffState;

  self.toggleDisplayMenuItem.state = [GVUserDefaults standardUserDefaults].toggleTargetDisplayMode ? NSOnState : NSOffState;
  self.toggleSleepMenuItem.state = [GVUserDefaults standardUserDefaults].toggleDisableSleep ? NSOnState : NSOffState;
  self.toggleLaunchAtLoginMenuItem.state = [GVUserDefaults standardUserDefaults].toggleLaunchAtLogin ? NSOnState : NSOffState;

  [self setupLaunchAtLogin];

  self.connectionStatusMenuItem.title = [NSString stringWithFormat:@"%@: %@", [self modeString], NSLocalizedString(@"Initializing …", comment:"State when the application is initializing.")];

  if (self.isClient) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidChangeScreenParametersNotification:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
      [self updateConnectionState:[self clientIsInTargetDisplayMode]];
    self.toggleDisplayMenuItem.hidden = YES;
    NSLog(NSLocalizedString(@"Running in %@.", comment:@"Example: Running in Client Mode."), [self modeString]);
  } else {
    self.toggleSleepMenuItem.hidden = YES;
    [GVUserDefaults standardUserDefaults].toggleDisableSleep = NO;
  }

  self.statusItem = [KVMStatusItem statusItemWithMenu:self.menu];
}

#pragma mark - NSApplicationDidChangeScreenParametersNotification

- (void)applicationDidChangeScreenParametersNotification:(NSNotification *)notifcation {
  [self updateConnectionState:[self clientIsInTargetDisplayMode]];
}

#pragma mark - Menu Actions

- (IBAction)toggleTargetDisplayOption:(id)sender {
  NSMenuItem *menuItem = (NSMenuItem *)sender;

  if (menuItem.state == NSOnState) {
    menuItem.state = NSOffState;
  } else {
    menuItem.state = NSOnState;
  }

  [GVUserDefaults standardUserDefaults].toggleTargetDisplayMode = menuItem.state == NSOnState;
}

- (IBAction)toggleBluetoothOption:(id)sender {
  NSMenuItem *menuItem = (NSMenuItem *)sender;

  if (menuItem.state == NSOnState) {
    menuItem.state = NSOffState;
  } else {
    menuItem.state = NSOnState;
  }

  [GVUserDefaults standardUserDefaults].toggleBluetooth = menuItem.state == NSOnState;
}

- (IBAction)toggleSleepOption:(id)sender {
  NSMenuItem *menuItem = (NSMenuItem *)sender;

  if (menuItem.state == NSOnState) {
    menuItem.state = NSOffState;
  } else {
    menuItem.state = NSOnState;
  }

  [GVUserDefaults standardUserDefaults].toggleDisableSleep = menuItem.state == NSOnState;
}

- (IBAction)toggleLaunchAtLoginOption:(id)sender {
  NSMenuItem *menuItem = (NSMenuItem *)sender;

  if (menuItem.state == NSOnState) {
    menuItem.state = NSOffState;
  } else {
    menuItem.state = NSOnState;
  }

  [GVUserDefaults standardUserDefaults].toggleLaunchAtLogin = menuItem.state == NSOnState;

  [self setupLaunchAtLogin];
}

- (void)setupLaunchAtLogin {
  NSString *helperApp = @"com.fastwombat.VirtualKVMHelper";

  if (self.toggleLaunchAtLoginMenuItem.state == YES) {
    NSLog(@"Turn on Launch At Login.");
    if (!SMLoginItemSetEnabled((__bridge CFStringRef)helperApp, YES)) {
      NSAlert *alert = [NSAlert alertWithMessageText:@"An error ocurred" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Couldn't add Helper App to login item list."];
      [alert runModal];
    }
  } else if (self.toggleLaunchAtLoginMenuItem.state == NSOffState) {
    NSLog(@"Turn off Launch At Login.");
    if (!SMLoginItemSetEnabled((__bridge CFStringRef)helperApp, NO)) {
      NSAlert *alert = [NSAlert alertWithMessageText:@"An error ocurred" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Couldn't remove Helper App from login item list."];
      [alert runModal];
    }
  }
}

- (IBAction)quit:(id)sender {
  [[NSApplication sharedApplication] terminate:self];
}

#pragma mark - KVMThunderboltObserverDelegate

- (void)thunderboltObserverDeviceConnected:(KVMThunderboltObserver *)observer {
  NSLog(NSLocalizedString(@"Thunderbolt device connected.", comment:nil));
  [self updateConnectionState:YES];

  if ([GVUserDefaults standardUserDefaults].toggleTargetDisplayMode) {
    [self enableTargetDisplayMode];
  }

  if ([GVUserDefaults standardUserDefaults].toggleBluetooth) {
    if (self.isClient) {
      [[KVMBluetoothController sharedController] enableBluetooth];
    } else {
      [[KVMBluetoothController sharedController] disableBluetooth];
    }
  }
}

- (void)thunderboltObserverDeviceDisconnected:(KVMThunderboltObserver *)observer {
  NSLog(NSLocalizedString(@"Thunderbolt device disconnected.", comment:nil));
  [self updateConnectionState:NO];

  if ([GVUserDefaults standardUserDefaults].toggleTargetDisplayMode) {
    [self disableTargetDisplayMode];
  }

  if ([GVUserDefaults standardUserDefaults].toggleBluetooth) {
    if (self.isClient) {
      [[KVMBluetoothController sharedController] disableBluetooth];
    } else {
      [[KVMBluetoothController sharedController] enableBluetooth];
    }
  }
}

- (void)thunderboltObserver:(KVMThunderboltObserver *)observer isInitiallyConnected:(BOOL)connected {
  [self updateConnectionState:connected];

  if (connected) {
    if ([GVUserDefaults standardUserDefaults].toggleTargetDisplayMode) {
      [self enableTargetDisplayMode];
    }
  }
}

- (void)updateConnectionState:(BOOL)connected {

  if (!self.isClient) {
    self.connectionStatusMenuItem.title = [NSString stringWithFormat:@"%@: %@", [self modeString], NSLocalizedString(@"Ready to Accept Connections", comment:nil)];
    return;
  }
  if (connected && [self clientIsInTargetDisplayMode]) {
    self.connectionStatusMenuItem.title = [NSString stringWithFormat:@"%@: %@", [self modeString], NSLocalizedString(@"Connected", comment:nil)];
    [self createPowerAssertion];
  } else {
    self.connectionStatusMenuItem.title = [NSString stringWithFormat:@"%@: %@", [self modeString], NSLocalizedString(@"Not Connected", comment:nil)];
    [self disableTargetDisplayMode];
  }
}

#pragma mark - Helpers

- (void)enableTargetDisplayMode {
  NSLog(@"Attempting to enable TDM.");
  if (self.thunderboltObserver.isInTargetDisplayMode || self.clientIsInTargetDisplayMode) {
    NSLog(@"Early return when attempting to enable TDM.");
    return;
  }

  CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

  CGEventRef f2d = CGEventCreateKeyboardEvent(src, 0x90, true);
  CGEventRef f2u = CGEventCreateKeyboardEvent(src, 0x90, false);

  CGEventSetFlags(f2d, kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskCommand);
  CGEventSetFlags(f2u, kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskCommand);

  CGEventTapLocation loc = kCGHIDEventTap;
  CGEventPost(loc, f2d);
  CGEventPost(loc, f2u);

  CFRelease(f2d);
  CFRelease(f2u);
  CFRelease(src);

}

- (void)createPowerAssertion {

  if (!self.isClient) {
    return;
  }

  // If we already have an `_sleepAssertion` then we are already holding a power assertion.
  if (self.sleepAssertion) {
    return;
  }

  self.assertionType = nil;

  if ([GVUserDefaults standardUserDefaults].toggleDisableSleep) {
    self.assertionType = kIOPMAssertPreventUserIdleDisplaySleep;
  } else {
    self.assertionType = kIOPMAssertPreventUserIdleSystemSleep;
  }
  CFStringRef reasonForActivity = (__bridge CFStringRef)@"In Target Display Mode";
  IOReturn success = IOPMAssertionCreateWithName(self.assertionType, kIOPMAssertionLevelOn, reasonForActivity, &_sleepAssertion);

  if (success == kIOReturnSuccess) {
    NSLog(NSLocalizedString(@"Created power assertion. Assertion type: %@", comment:nil), self.assertionType);
  } else {
    NSLog(NSLocalizedString(@"Unable to create power assertion.", comment:nil));
  }

}

- (void)disableTargetDisplayMode {
  if (self.sleepAssertion != kIOPMNullAssertionID) {
    IOReturn success = IOPMAssertionRelease(self.sleepAssertion);

    if (success == kIOReturnSuccess) {
      self.sleepAssertion = kIOPMNullAssertionID;
      NSLog(NSLocalizedString(@"Released power assertion. Assertion type: %@", comment:nil),self.assertionType);
    } else {
      NSLog(NSLocalizedString(@"Unable to release power assertion. Assertion type: %@", comment:nil),self.assertionType);
    }
  }
}

#pragma mark - Target Display Mode Status

- (BOOL)clientIsInTargetDisplayMode {

  if (!self.isClient) {
    return NO;
  }

  // Will have multiple objects if the the MacBook is in normal mode.
  // However, when in "closed-clamshell" mode `screens` should contain only contain 1 object,
  // this object will be the iMac's screen.
  NSArray *screens = [NSScreen screens];

  if (screens.count == 0) {
    return NO;
  }

  NSMutableArray <NSNumber *> *screenNumbers = [NSMutableArray new];
  for (NSScreen *screen in screens) {
    if (screen.deviceDescription[@"NSScreenNumber"]) {
      [screenNumbers addObject:@([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue])];
    }
  }

  if (screenNumbers.count == 0) {
    return NO;
  }

  NSMutableArray <NSString *> *localizedScreenNames = [NSMutableArray new];

  for (NSNumber *screenNumber in screenNumbers) {

    NSString *localizedScreenName = [self screenNameForDisplay:screenNumber.unsignedIntValue];
    if (localizedScreenName && localizedScreenName.length != 0) {
      [localizedScreenNames addObject:localizedScreenName];
      //For testing: [localizedScreenNames addObject:@"iMac"];
    }
  }

  if (localizedScreenNames.count == 0) {
    return NO;
  }

  for (NSString *localizedScreenName in localizedScreenNames) {
    if ([localizedScreenName isEqualToString:@"iMac"]) {
      return YES;
      break;
    }
  }

  return NO;
}

- (NSString *)screenNameForDisplay:(CGDirectDisplayID)displayID {

  NSString *screenName = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  NSDictionary *deviceInfo = (__bridge NSDictionary *)IODisplayCreateInfoDictionary(CGDisplayIOServicePort(displayID), kIODisplayOnlyPreferredName);
  #pragma clang diagnostic pop
  NSDictionary *localizedNames = [deviceInfo objectForKey:[NSString stringWithUTF8String:kDisplayProductName]];

  if ([localizedNames count] > 0) {
    screenName = [localizedNames objectForKey:[[localizedNames allKeys] objectAtIndex:0]];
  }

  return screenName;
}

@end
