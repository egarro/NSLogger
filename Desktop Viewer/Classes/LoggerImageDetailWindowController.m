/*
 * LoggerImageDetailWindowController.m
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010-2011 Florent Pillet <fpillet@gmail.com> All Rights Reserved.
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
#import "LoggerImageDetailWindowController.h"
#import "LoggerWindowController.h"
#import "LoggerDocument.h"
#import "LoggerMessage.h"
#import "LoggerMessageCell.h"

#import "NSStringAdditions.h"

@implementation LoggerImageDetailWindowController

@synthesize imageString = _imageString;
@synthesize imageInfo = _imageInfo;
@synthesize theImage = _theImage;

- (void)dealloc
{
	[super dealloc];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
	return [[[self document] mainWindowController] windowTitleForDocumentDisplayName:displayName];
}

- (void)windowDidLoad
{
	[self.imageString setTextContainerInset:NSMakeSize(2, 2)];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
	[[self.document mainWindowController] updateMenuBar:YES];
}

- (void)windowDidResignMain:(NSNotification *)notification
{
	[[self.document mainWindowController] updateMenuBar:YES];
}

- (void)setImage:(NSImage *)image withInfo:(NSString *)info
{
	// defer text generation to queues
	NSTextStorage *storage = [self.imageString textStorage];
	[storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:@""];

	[self.imageInfo setStringValue:info];

    [self.theImage setImage:image];
    
    //Transform the image into a base64 string?
    NSBitmapImageRep *imgRep = [[image representations] objectAtIndex:0];
    NSData *data = [imgRep representationUsingType:NSPNGFileType properties:nil];
    NSString *someString = [NSString base64forData:data];
    
    [storage beginEditing];
        [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:someString];
    [storage endEditing];
    
}

-(IBAction)saveTo:(id)sender {
    NSArray *components = [self.imageInfo.stringValue componentsSeparatedByString:@" | "];
    NSString *num = [components objectAtIndex:0];
    NSString *tmp = [components objectAtIndex:2];
    [self exportDocument:[NSString stringWithFormat:@"%@%@.png",tmp,num]];
}

- (void)exportDocument:(NSString*)name
{    
    // Set the default name for the file and show the panel.
    NSSavePanel*    panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:name];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton)
        {
            NSURL*  theFile = [panel URL];
            NSBitmapImageRep *imgRep = [[self.theImage.image representations] objectAtIndex:0];
            NSData *data = [imgRep representationUsingType:NSPNGFileType properties:nil];
            [data writeToURL:[theFile absoluteURL] atomically: NO];
        }
    }];
}

@end
