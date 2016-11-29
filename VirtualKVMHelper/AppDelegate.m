//
//  AppDelegate.m
//  VirtualKVMHelper
//
//  Created by Markus Reiter on 28.11.16.
//  Copyright © 2016 Fast Wombat. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  NSArray *runningInstances = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.fastwombat.VirtualKVM"];
  
  if([runningInstances count] == 0) {
    NSString *path = [[NSBundle mainBundle] bundlePath];
    NSArray *p = [path pathComponents];
    
    NSMutableArray *pathComponents = [NSMutableArray arrayWithArray:p];
    [pathComponents removeLastObject];
    [pathComponents removeLastObject];
    [pathComponents removeLastObject];
    [pathComponents addObject:@"MacOS"];
    [pathComponents addObject:@"VirtualKVM"];
    
    NSString *executablePath = [NSString pathWithComponents:pathComponents];
    [[NSWorkspace sharedWorkspace] launchApplication:executablePath];

  }
  
  [NSApp terminate:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {

}

@end
