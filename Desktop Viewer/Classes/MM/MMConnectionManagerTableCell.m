/*
 * MMConnectionManagerTableCell.m
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2011 Esteban Garro <e.garro@mademediacorp.com> All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * Redistributions of  source code  must retain  the above  copyright notice,
 * this list of  conditions and the following  disclaimer. Redistributions in
 * binary  form must  reproduce  the  above copyright  notice,  this list  of
 * conditions and the following disclaimer  in the documentation and/or other
 * materials  provided with  the distribution.  Neither the  name of  Florent
 * Pillet nor the names of its contributors may be used to endorse or promote
 * products  derived  from  this  software  without  specific  prior  written
 * permission.  THIS  SOFTWARE  IS  PROVIDED BY  THE  COPYRIGHT  HOLDERS  AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT
 * NOT LIMITED TO, THE IMPLIED  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A  PARTICULAR PURPOSE  ARE DISCLAIMED.  IN  NO EVENT  SHALL THE  COPYRIGHT
 * HOLDER OR  CONTRIBUTORS BE  LIABLE FOR  ANY DIRECT,  INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY,  OR CONSEQUENTIAL DAMAGES (INCLUDING,  BUT NOT LIMITED
 * TO, PROCUREMENT  OF SUBSTITUTE GOODS  OR SERVICES;  LOSS OF USE,  DATA, OR
 * PROFITS; OR  BUSINESS INTERRUPTION)  HOWEVER CAUSED AND  ON ANY  THEORY OF
 * LIABILITY,  WHETHER  IN CONTRACT,  STRICT  LIABILITY,  OR TORT  (INCLUDING
 * NEGLIGENCE  OR OTHERWISE)  ARISING  IN ANY  WAY  OUT OF  THE  USE OF  THIS
 * SOFTWARE,   EVEN  IF   ADVISED  OF   THE  POSSIBILITY   OF  SUCH   DAMAGE.
 * 
 */

#import "MMConnectionManagerTableCell.h"
#import "LoggerAppDelegate.h"
#import "LoggerDocument.h"

@implementation MMConnectionManagerTableCell

@synthesize desc, status, state;


- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{

    NSArray *documents = ((LoggerAppDelegate *)[NSApp delegate]).documents;
	LoggerDocument *document = [documents objectAtIndex:[[self objectValue] integerValue]];
    
	BOOL highlighted = [self isHighlighted];
    
	// Display status image
	NSString *imgName;
    
    switch (state) {
        case 1:
            imgName = NSImageNameStatusAvailable;
            break;
        case 2:
            imgName = NSImageNameStatusUnavailable;
            break;
        case 3:
            imgName = NSImageNameStatusPartiallyAvailable;
            break;
        default:
            imgName = NSImageNameStatusNone;
            break;
    }

    CGFloat h = 5.0;
    
	NSImage *img = [NSImage imageNamed:imgName];
    NSSize sz = [img size];
    
	if (img != nil)
	{
		[img drawInRect:NSMakeRect(NSMinX(cellFrame) + 5.0,
								   NSMinY(cellFrame) + 2*h,
								   sz.width,
								   sz.height)
			   fromRect:NSMakeRect(0, 0, sz.width, sz.height)
			  operation:NSCompositeSourceOver
			   fraction:1.0f
		 respectFlipped:YES
				  hints:nil];

	}

    
    if (document.currentConnection.isWiFi) imgName = @"wifi_bars.png";
    else imgName = @"cellphone_bars.png";
    
    NSImage *connectionImg = [NSImage imageNamed:imgName];
    NSSize szConn = NSZeroSize;
	if (connectionImg != nil) {
		szConn = [connectionImg size];
        [connectionImg drawInRect:NSMakeRect(NSMaxX(cellFrame) - szConn.width - 5.0,
                                      NSMaxY(cellFrame) - szConn.height - 5.0,
                                      szConn.width,
                                      szConn.height)
                  fromRect:NSMakeRect(0, 0, szConn.width, szConn.height)
                 operation:NSCompositeSourceOver
                  fraction:1.0f
            respectFlipped:YES
                     hints:nil];
    
    }

        
	NSFont *descFont = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
	NSFont *statusFont = [NSFont systemFontOfSize:[NSFont systemFontSize] - 2];
	
	NSColor *textColor = (highlighted ? [NSColor grayColor] : [NSColor whiteColor]);
	NSDictionary *descAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
							   descFont, NSFontAttributeName,
							   textColor, NSForegroundColorAttributeName,
							   [NSColor clearColor], NSBackgroundColorAttributeName,
							   nil];
	
	if (!highlighted)
	{
			textColor = [NSColor grayColor];
	}
	NSDictionary *statusAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
								 statusFont, NSFontAttributeName,
								 textColor, NSForegroundColorAttributeName,
								 [NSColor clearColor], NSBackgroundColorAttributeName,
								 nil];
	
	NSSize descSize = [self.desc sizeWithAttributes:descAttrs];
	NSSize statusSize = [self.status sizeWithAttributes:statusAttrs];
	
	CGFloat w = sz.width + 10.0;
	
	NSRect r = NSMakeRect(NSMinX(cellFrame) + w,
                          NSMinY(cellFrame) + h, NSWidth(cellFrame) - w, descSize.height);
	[self.desc drawInRect:r withAttributes:descAttrs];
    
	r.origin.y += r.size.height + 2;
	r.size.height = statusSize.height;
    [self.status drawInRect:r withAttributes:statusAttrs];
    
    
    NSString *crashcount = document.currentConnection.clientCrashCount;
    if (crashcount != (id)[NSNull null] &&
        crashcount != nil &&
        ![crashcount isEqualToString:@""] &&
        ![crashcount isEqualToString:@" "] &&
        ![crashcount isEqualToString:@"0"]) {
        
        NSImage *crashImg = [NSImage imageNamed:@"crash_bomb.png"];
        NSSize szCrash = NSZeroSize;
        if (crashImg != nil) {
            szCrash = [crashImg size];
            [crashImg drawInRect:NSMakeRect(NSMaxX(cellFrame) - szConn.width - 5.0 - szCrash.width - 5.0,
                                                 NSMaxY(cellFrame) - szCrash.height - 5.0,
                                                 szCrash.width,
                                                 szCrash.height)
                             fromRect:NSMakeRect(0, 0, szCrash.width, szCrash.height)
                            operation:NSCompositeSourceOver
                             fraction:1.0f
                       respectFlipped:YES
                                hints:nil];
            
        }
        
        NSSize crashSize = [crashcount sizeWithAttributes:descAttrs];
        
        r = NSMakeRect(NSMaxX(cellFrame) - szConn.width - 5.0 - szCrash.width - 5.0 - crashSize.width - 5.0,
                       NSMaxY(cellFrame) - crashSize.height - 10.0, crashSize.width, crashSize.height);
        
        [crashcount drawInRect:r withAttributes:descAttrs];
        
    }
    
}


@end
