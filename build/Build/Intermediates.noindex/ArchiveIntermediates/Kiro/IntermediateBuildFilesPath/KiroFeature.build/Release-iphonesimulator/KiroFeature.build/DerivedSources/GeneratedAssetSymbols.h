#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "tiko_avatar" asset catalog image resource.
static NSString * const ACImageNameTikoAvatar AC_SWIFT_PRIVATE = @"tiko_avatar";

/// The "tiko_mushroom" asset catalog image resource.
static NSString * const ACImageNameTikoMushroom AC_SWIFT_PRIVATE = @"tiko_mushroom";

/// The "tiko_reading" asset catalog image resource.
static NSString * const ACImageNameTikoReading AC_SWIFT_PRIVATE = @"tiko_reading";

#undef AC_SWIFT_PRIVATE
