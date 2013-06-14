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


- (NSString *)babyDecrypt {

        NSData* decodedBase64data = [Encode Base64Decode:self];
        NSString *resp = [EncryptionController decryptData:decodedBase64data withKey:ENCRYPT_KEY andVector:babyEncryptKey];
    
        return resp;
}


@end
