//
//  NSData+Encryption.h
//  FII-Application
//
//  Created by Kien Hung Tran on 11-05-26.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

/*!
	@category
		NSData+Encryption
	@abstract
		Adds encryption methods to NSData.
 */
@interface NSData (Encryption)

/*!
	@method
		AES256EncryptWithKey:andVector
	@abstract
		Encrypts the implicit data object.
	@param
		NSString *key - Encryption key
	@param
		NSString *initVector -
	@return
		NSData - Encrypted data object.  Autoreleased.
 */
-(NSData *)AES256EncryptWithKey:(NSString *)key andVector:(NSString *)initVector;

/*!
	@method
		AES256DecryptWithKey:andVector
	@abstract
		Decrypts the implicit NSData object.
	@discussion
	@param
		NSString *key - Decryption key.
	@param
		NSString *initVector -
	@return
		NSData - Decrypted NSData object.  Autoreleased.
 */
-(NSData *)AES256DecryptWithKey:(NSString *)key andVector:(NSString *)initVector;

@end