//
//  NSStringAdditions.h
//  XMLTest
//
//  Created by  on 12-06-15.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//


@interface NSString (myAdditions)

+ (NSString*)base64forData:(NSData*)theData;
- (NSString *)babyDecrypt;

@end

