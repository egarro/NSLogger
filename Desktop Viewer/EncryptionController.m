//
//  EncryptionController.m
//  Fii-Canada
//
//  Created by  on 12-01-27.
//  Copyright (c) 2012 Made Media. All rights reserved.
//

#import "EncryptionController.h"
#import "NSData+Encryption.h"

@implementation EncryptionController

+(NSString*) decryptData:(NSData*)ciphertext withKey:(NSString*)key andVector:(NSString *)initVector {
    return [[NSString alloc] initWithData:[ciphertext AES256DecryptWithKey:key andVector:initVector]
                                  encoding:NSUTF8StringEncoding];
}
@end
