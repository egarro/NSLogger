//
//  EncryptionController.h
//  Fii-Canada
//
//  Created by  on 12-01-27.
//  Copyright (c) 2012 Made Media. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EncryptionController : NSObject

/*!
	@method
		decryptData:withKey:andVector;
	@abstract
		Decrypts the provided NSData object, and returns a the plain text string.
	@discussion
	@param
		NSData *cipherText - Data object to be decrypted.
	@param
		NSString *key - decryption key.
	@param
		NSString *initViector -
	@return
		NSString -  decrypted plain text string.  Autoreleased.
 */
+(NSString *)decryptData:(NSData *)ciphertext withKey:(NSString *)key andVector:(NSString *)initVector;

@end
