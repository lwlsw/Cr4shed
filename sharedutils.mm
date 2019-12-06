@import Foundation;

#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld_images.h>
#import "MobileGestalt/MobileGestalt.h"
#import "sharedutils.h"

NSString* getImage(NSString* symbol)
{
    int startingI = -1;
    int endingI = -1;
    for (int i = 0; i < symbol.length - 1; i++)
    {
        char c = [symbol characterAtIndex:i];
        char nextC = [symbol characterAtIndex:i+1];
        if (startingI == -1)
        {
            if (c == ' ' && nextC != ' ')
            {
                startingI = i+1;
            }
        }
        else
        {
            if (nextC == ' ')
            {
                endingI = i+1;
                break;
            }
        }
    }
    return [symbol substringWithRange:NSMakeRange(startingI, endingI-startingI)];
}

NSString* determineCulprit(NSArray* symbols)
{
    for (int i = 0; i < symbols.count; i++)
    {
        NSString* symbol = symbols[i];
        NSString* image = getImage(symbol);
        if (![image isEqualToString:@"Cr4shed.dylib"])
        {
            if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"/Library/MobileSubstrate/DynamicLibraries/%@", image]])
                return image;
        }
    }
    return @"Unknown";
}

NSString* stringFromDate(NSDate* date, CR4DateFormat type)
{
    BOOL needsLowercase = NO;
    NSDateFormatter* formatter = [NSDateFormatter new];
	switch (type)
	{
		case CR4DateFormatPretty:
			[formatter setDateStyle:NSDateFormatterShortStyle];
    		[formatter setTimeStyle:NSDateFormatterShortStyle];
			break;
		case CR4DateFormatFilename:
            needsLowercase = YES;
			[formatter setDateFormat:@"yyyy-MM-dd_h:mm_a"];
			break;
		default:
			return @"Unknown format type! :(";
	}
    NSString* ret = [formatter stringFromDate:date];
    return needsLowercase ? [ret lowercaseString] : ret;
}

NSString* deviceVersion()
{
    return (__bridge NSString*)MGCopyAnswer(CFSTR("ProductVersion")) ?: @"Unknown";
}

NSString* deviceName()
{
    return (__bridge NSString*)MGCopyAnswer(CFSTR("marketing-name")) ?: @"Unknown";
}

#define MAX_CHUNK_SIZE 0xFFF
#ifdef __cplusplus
extern "C" {
#endif
kern_return_t mach_vm_read_overwrite(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, mach_vm_address_t data, mach_vm_size_t *outsize);
kern_return_t mach_vm_write(vm_map_t target_task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t dataCnt);
#ifdef __cplusplus
}
#endif

size_t rread(mach_port_t task, mach_vm_address_t where, void* p, size_t size)
{
    kern_return_t rv;
    size_t offset = 0;
    while (offset < size)
	{
        mach_vm_size_t sz, chunk = MAX_CHUNK_SIZE;
        if (chunk > size - offset)
            chunk = size - offset;
        rv = mach_vm_read_overwrite(task, where + offset, chunk, (mach_vm_address_t)p + offset, &sz);
        if (rv || sz == 0)
            break;
        offset += sz;
    }
    return offset;
}

size_t rwrite(mach_port_t task, mach_vm_address_t where, const void* p, size_t size)
{
    kern_return_t rv;
    size_t offset = 0;
    while (offset < size)
	{
        size_t chunk = MAX_CHUNK_SIZE;
        if (chunk > size - offset)
            chunk = size - offset;
        rv = mach_vm_write(task, where + offset, (mach_vm_offset_t)p + offset, chunk);
        if (rv)
            break;
        offset += chunk;
    }
    return offset;
}

mach_vm_address_t taskGetImageInfos(mach_port_t task)
{
    struct task_dyld_info dyld_info = {0};
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (kr == KERN_SUCCESS && dyld_info.all_image_info_addr && dyld_info.all_image_info_size)
        return dyld_info.all_image_info_addr;
    return 0;
}

//used to let Cr4shedMach know that this process' crash
//has been dealt with
const char* const flag = "com.muirey03.cr4shed-exceptionHandled";

void markProcessAsHandled(mach_port_t task)
{
    mach_vm_address_t image_infos = taskGetImageInfos(task);
    if (image_infos)
        rwrite(task, image_infos + offsetof(struct dyld_all_image_infos, errorMessage), (void*)&flag, sizeof(const char*));
}

bool processHasBeenHandled(mach_port_t task)
{
    bool handled = false;
    mach_vm_address_t image_infos = taskGetImageInfos(task);
    if (image_infos)
    {
        uint64_t errorMsgAddr = 0;
        rread(task, image_infos + offsetof(struct dyld_all_image_infos, errorMessage), (void*)&errorMsgAddr, sizeof(uint64_t));
        if (errorMsgAddr)
        {
            void* mem = malloc(strlen(flag) + 1);
            if (mem)
            {
                rread(task, errorMsgAddr, mem, strlen(flag) + 1);
                handled = (memcmp(mem, flag, strlen(flag)) == 0);
                free(mem);
            }
        }
    }
    return handled;
}
