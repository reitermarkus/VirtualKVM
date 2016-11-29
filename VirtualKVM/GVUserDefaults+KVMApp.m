#import "GVUserDefaults+KVMApp.h"

@implementation GVUserDefaults (KVMApp)

@dynamic toggleBluetooth;
@dynamic toggleTargetDisplayMode;
@dynamic toggleDisableSleep;
@dynamic toggleLaunchAtLogin;

- (NSDictionary *)setupDefaults {
  return @{
    @"toggleBluetooth": @YES,
    @"toggleTargetDisplayMode": @YES,
    @"toggleDisableSleep": @YES,
    @"toggleLaunchAtLogin": @NO,
  };
}

@end
