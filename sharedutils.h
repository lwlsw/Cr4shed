#include <mach/mach.h>

typedef NS_ENUM(NSInteger, CR4DateFormat)
{
    CR4DateFormatPretty,
    CR4DateFormatFilename
};

#ifdef __cplusplus
extern "C" {
#endif
NSString* getImage(NSString* symbol);
NSString* determineCulprit(NSArray* symbols);
NSString* stringFromDate(NSDate* date, CR4DateFormat type);
NSString* deviceVersion();
NSString* deviceName();
size_t rread(mach_port_t task, mach_vm_address_t where, void* p, size_t size);
size_t rwrite(mach_port_t task, mach_vm_address_t where, const void* p, size_t size);
mach_vm_address_t taskGetImageInfos(mach_port_t task);
void markProcessAsHandled(void);
bool processHasBeenHandled(mach_port_t task);
#ifdef __cplusplus
}
#endif
