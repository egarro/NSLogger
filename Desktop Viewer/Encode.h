//
//  Encode.h
//  FII-Application
//
//  http://stackoverflow.com/questions/882277/how-to-base64-encode-on-the-iphone
//  Copyright 2010 Concordia University. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface Encode : NSObject 
{
}

+ (NSString *)Base64Encode:(NSData *)data;
+ (NSData *)Base64Decode:(NSString *)strBase64;
@end
