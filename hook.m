#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// the swizzling function :p
void swizzie(Class targetClass, char* selectorName, id block, char* types)
{
  if (!targetClass)
    return;
  SEL selector = sel_registerName(selectorName);
  class_replaceMethod(targetClass, selector, imp_implementationWithBlock(block), types);
}

__attribute__((constructor)) static void setup()
{
  // try to force the license status
  swizzie(objc_getClass("CXApplication"), "isLicensed", ^BOOL(id self) { return YES; }, "B@:");
  swizzie(objc_getClass("CXApplication"), "isTrial", ^BOOL(id self) { return NO; }, "B@:");
  swizzie(objc_getClass("CXApplication"), "daysLeft", ^NSInteger(id self) { return 9999; }, "q@:");

  // hook into the pyobjc methods
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
      Class demoUtils = nil;
      for (int i = 0; i < 100; i++) {
        demoUtils = objc_lookUpClass("DemoUtils");
        if (demoUtils) {
          swizzie(demoUtils, "demoStatusForLicenseFile:andSig:", ^id(id self, id lic, id sig) { return @[ @NO, @"crazy", @"2099-01-01", @"i was crazy once", @NO ]; }, "@@:@@");
          break;
        }
        usleep(100000);
      }
  });

  // hook into the nag controller
  Class nagClass = objc_getClass("DemoNagController");
  if (nagClass) {
    swizzie(
        nagClass, "showWindow:",
        ^void(id self, id sender) {
            if ([self respondsToSelector:@selector(runapp:)]) {
              // calling the runapp method on the class essentially bypasses the nag without showing the window
              [self performSelector:@selector(runapp:) withObject:nil];
            } else {
              NSLog(@"ok well if ur getting this either u actaully registered/paid for the app or somehow ur crossover is screwed up and doesnt have the runapp method");
            }
        },
        "v@:@");
  }
  // suppress the expired strings because :3
  swizzie(objc_getClass("DemoBaseController"), "setExpirationText:", ^void(id self, id text) {}, "v@:@");
}