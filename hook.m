#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <libkern/OSCacheControl.h>

// signature: push rdi; push rsi; push rbx; sub rsp, 0x50
// basically this is what crossover uses to check if the "trial" expired
static unsigned char TARGET[] = { 0x57, 0x56, 0x53, 0x48, 0x83, 0xEC, 0x50 };
// how to paatch: xor eax, eax; ret
static unsigned char PATCH[]  = { 0x31, 0xC0, 0xC3 };
static bool g_patch_applied = false;

// makes it easier to debuglater so im leaving this in here
void logg(NSString *msg) {
  NSString *logPath = @"/tmp/crossover_patch.log";
  NSString *entry = [NSString stringWithFormat:@"%@\n", msg];
  NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
  if (!fh) {
    [entry writeToFile:logPath
            atomically:YES
              encoding:NSUTF8StringEncoding
                 error:nil];
  } else {
    [fh seekToEndOfFile];
    [fh writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
  }
}
// just find the mem address using the signature and patch it
void scan_and_patch() {
  if (g_patch_applied)
    return;
  task_t task = mach_task_self();
  vm_address_t address = 0;
  vm_size_t size = 0;

  while (true) {
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    if (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64,
                     (vm_region_info_t)&info, &count,
                     &object_name) != KERN_SUCCESS)
      break;

    // my signature is a bit common and accesses stack heaps so we need to target low memory to avoid stack crashes
    if (address > 0x200000000) {
      address += size;
      continue;
    }

    if ((info.protection & VM_PROT_EXECUTE) &&
        (info.protection & VM_PROT_READ)) {
      unsigned char *buf = (unsigned char *)address;
      if (size < sizeof(TARGET)) {
        address += size;
        continue;
      }

      for (size_t i = 0; i < size - sizeof(TARGET); i++) {
        if (memcmp(buf + i, TARGET, sizeof(TARGET)) == 0) {
          vm_address_t pAddr = address + i;

          if (memcmp(buf + i, PATCH, sizeof(PATCH)) == 0) {
            g_patch_applied = true;
            return;
          }

          logg([NSString stringWithFormat:@"patchhing wineloader/wrapper at %p",
                                          (void *)pAddr]);
          vm_protect(task, pAddr, sizeof(PATCH), false,
                     VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
          memcpy((void *)pAddr, PATCH, sizeof(PATCH));
          vm_protect(task, pAddr, sizeof(PATCH), false,
                     VM_PROT_READ | VM_PROT_EXECUTE);
          sys_icache_invalidate((void *)pAddr, sizeof(PATCH));

          g_patch_applied = true;
          logg(@"wowie it patched the license check");
          return;
        }
      }
    }
    address += size;
  }
}

void swizzie(Class cls, char *sel, id block, char *sig) {
  if (cls)
    class_replaceMethod(cls, sel_registerName(sel),
                        imp_implementationWithBlock(block), sig);
}

void reset_bottles() {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *bottlesPath = [@"~/Library/Application Support/CrossOver/Bottles"
      stringByExpandingTildeInPath];
  NSError *error = nil;
  NSArray *bottles = [fm contentsOfDirectoryAtPath:bottlesPath error:&error];

  if (error) {
    logg([NSString stringWithFormat:@"something went wrong reading the bottles dir: %@",
                                    error.localizedDescription]);
    return;
  }

  for (NSString *bottle in bottles) {
    NSString *bottlePath = [bottlesPath stringByAppendingPathComponent:bottle];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:bottlePath isDirectory:&isDir] && isDir) {
      NSString *timestampPath =
          [bottlePath stringByAppendingPathComponent:@".update-timestamp"];
      if ([fm fileExistsAtPath:timestampPath]) {
        [fm removeItemAtPath:timestampPath error:nil];
        logg([NSString
            stringWithFormat:@"Removed timestamp for bottle: %@", bottle]);
      }

      NSString *regPath =
          [bottlePath stringByAppendingPathComponent:@"system.reg"];
      if ([fm fileExistsAtPath:regPath]) {
        NSString *content =
            [NSString stringWithContentsOfFile:regPath
                                      encoding:NSUTF8StringEncoding
                                         error:nil];
        if (content) {
          NSRange startRange = [content
              rangeOfString:
                  @"[Software\\\\CodeWeavers\\\\CrossOver\\\\cxoffice]"];
          if (startRange.location != NSNotFound) {
            NSRange searchRange = NSMakeRange(
                startRange.location, content.length - startRange.location);
            NSRange endRange = [content rangeOfString:@"\"Version\"="
                                              options:0
                                                range:searchRange];
            if (endRange.location != NSNotFound) {
              NSRange lineEndRange =
                  [content rangeOfString:@"\n"
                                 options:0
                                   range:NSMakeRange(endRange.location,
                                                     content.length -
                                                         endRange.location)];
              NSUInteger endPos = (lineEndRange.location != NSNotFound)
                                      ? lineEndRange.location + 1
                                      : endRange.location + endRange.length;

              NSString *newContent = [content
                  stringByReplacingCharactersInRange:NSMakeRange(
                                                         startRange.location,
                                                         endPos - startRange
                                                                      .location)
                                          withString:@""];
              [newContent writeToFile:regPath
                           atomically:YES
                             encoding:NSUTF8StringEncoding
                                error:nil];
              logg([NSString
                  stringWithFormat:@"Patched system.reg for bottle: %@",
                                   bottle]);
            }
          }
        }
      }
    }
  }
}

__attribute__((constructor)) static void setup() {
  unsetenv("DYLD_INSERT_LIBRARIES");

  char path[1024];
  uint32_t size = sizeof(path);
  _NSGetExecutablePath(path, &size);
  NSString *proc = [[NSString stringWithUTF8String:path] lastPathComponent];

  if ([proc containsString:@"CrossOver"]) {
    logg(@"blah blah hook gui");
    reset_bottles();
    swizzie(
        objc_getClass("CXApplication"), "isLicensed",
        ^BOOL(id s) {
          return YES;
        },
        "B@:");
    swizzie(
        objc_getClass("CXApplication"), "isTrial",
        ^BOOL(id s) {
          return NO;
        },
        "B@:");
    swizzie(
        objc_getClass("CXApplication"), "daysLeft",
        ^NSInteger(id s) {
          return 9999;
        },
        "q@:");
    swizzie(objc_getClass("DemoBaseController"), "setExpirationText:",
            ^void(id s, id t){
            },
            "v@:@");

    Class nag = objc_getClass("DemoNagController");
    if (nag)
      swizzie(
          nag, "showWindow:",
          ^void(id s, id sender) {
            if ([s respondsToSelector:@selector(runapp:)])
              [s performSelector:@selector(runapp:) withObject:nil];
          },
          "v@:@");

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
      for (int i = 0; i < 100; i++) {
        Class u = objc_lookUpClass("DemoUtils");
        if (u) {
          swizzie(
              u, "demoStatusForLicenseFile:andSig:",
              ^id(id s, id l, id si) {
                return
                    @[ @NO, @"crazy", @"2099-01-01", @"i was crazy once", @NO ];
              },
              "@@:@@");
          break;
        }
        usleep(100000);
      }
    });
  }
  // catch the wine engine
  else if ([proc containsString:@"wineloader"]) {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
      for (int i = 0; i < 300; i++) {
        if (g_patch_applied)
          break;
        scan_and_patch();
        usleep(50000);
      }
    });
  }
}