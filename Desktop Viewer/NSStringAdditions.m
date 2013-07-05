//
//  NSStringAdditions.m
//  XMLTest
//
//  Created by  on 12-06-15.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "NSStringAdditions.h"
#import "EncryptionController.h"
#import "Encode.h"

#define babyEncryptKey @"4566221239871021"
#define ENCRYPT_KEY    @"613d3939e5f32d369eedcc69af418319"

@implementation NSString (myAdditions)


+ (NSString*)base64forData:(NSData*)theData {
	
	const uint8_t* input = (const uint8_t*)[theData bytes];
	NSInteger length = [theData length];
	
    static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
	
    NSMutableData* data = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
    uint8_t* output = (uint8_t*)data.mutableBytes;
	
	NSInteger i,i2;
    for (i=0; i < length; i += 3) {
        NSInteger value = 0;
		for (i2=0; i2<3; i2++) {
            value <<= 8;
            if (i+i2 < length) {
                value |= (0xFF & input[i+i2]);
            }
        }
		
        NSInteger theIndex = (i / 3) * 4;
        output[theIndex + 0] =                    table[(value >> 18) & 0x3F];
        output[theIndex + 1] =                    table[(value >> 12) & 0x3F];
        output[theIndex + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
        output[theIndex + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
    }
	
    return [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
}


- (NSString *)babyDecrypt {
    
    NSData* decodedBase64data = [Encode Base64Decode:self];
    NSString *resp = [EncryptionController decryptData:decodedBase64data withKey:ENCRYPT_KEY andVector:babyEncryptKey];
    
    return resp;
}


@end
