//
//  UIDeviceAdditions.m
//  NSLoggerTestApp
//
//  Created by Esteban Garro on 13-03-05.
//
//

#import "IPAddress.h"

@implementation UIDevice (MMAdditions)


- (NSString *)macaddress {

    InitAddresses();
    GetIPAddresses();
    GetHWAddresses();
    
    int i;
    NSString *deviceIP = nil;
    
    for (i=0; i<MAXADDRS; ++i)
    {
        static unsigned long localHost = 0x7F000001;        // 127.0.0.1
        unsigned long theAddr;
        
        theAddr = ip_addrs[i];
        
        if (theAddr == 0) break;
        if (theAddr == localHost) continue;
        
//        NSLog(@"Name: %s MAC: %s IP: %s\n", if_names[i], hw_addrs[i], ip_names[i]);

//Decide what adapter you want details for
        if (strncmp(if_names[i], "en", 2) == 0)
        {
            deviceIP = [NSString stringWithCString:hw_addrs[i] encoding:NSASCIIStringEncoding];
            return deviceIP;
        }

    }
    
    return deviceIP;
    
}


@end