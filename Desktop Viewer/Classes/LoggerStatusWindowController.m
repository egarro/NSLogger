/*
 * LoggerStatusWindowController.h
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
#import "LoggerStatusWindowController.h"
#import "LoggerAppDelegate.h"
#import "LoggerTransport.h"
#import "LoggerConnection.h"
#import "LoggerTransportStatusCell.h"
#import "MMConnectionManagerWindowController.h"

NSString * const kShowStatusInStatusWindowNotification = @"ShowStatusInStatusWindowNotification";

@implementation LoggerStatusWindowController

@synthesize connectionController;

- (void)dealloc
{
	[transportStatusCell release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (void)windowDidLoad
{
	transportStatusCell = [[LoggerTransportStatusCell alloc] init];
    connectionController = nil;
    
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(showStatus:)
												 name:kShowStatusInStatusWindowNotification
											   object:nil];
	
	[[self window] setLevel:NSNormalWindowLevel];
}

- (void)showStatus:(NSNotification *)notification
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[statusTable reloadData];
	});
    
    if (connectionController != nil) {
        [connectionController reloadTable];
    }
}

//MM ADDITION POINT
-(void)reloadSubtable {
    if (connectionController != nil) {
        [connectionController reloadTable];
    }
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDelegate
// -----------------------------------------------------------------------------
- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < [((LoggerAppDelegate *)[NSApp delegate]).transports count])
		return transportStatusCell;
    
	return nil;
}

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
   return NO;
}


//MM ADDITION POINT
- (IBAction)tableViewDidSelectRow:(id)sender
{
    
    //MM ADDITION POINT:
    //Check whether we should add an entry to the Connection Manager or display a window.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPrefUseConnectionManager]) {
        
    
      NSInteger selectedRow = [(NSTableView *)sender clickedRow];
    
      NSArray *transports = ((LoggerAppDelegate *)[NSApp delegate]).transports;
      if (selectedRow < [transports count]) {
        NSString *cellInfo = [(LoggerTransport *)[transports objectAtIndex:selectedRow] transportInfoString];
        if (([cellInfo rangeOfString:@"TCP/IP"]).location != NSNotFound) {
            [(NSTableView *)sender selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];

            // Prepare the Connection Manager Window:
            if (connectionController == nil) {
 
                connectionController = [[MMConnectionManagerWindowController alloc] initWithWindowNibName:@"MMConnectionManager"];
                NSRect frame = self.window.frame;
                frame.origin.x -= connectionController.window.frame.size.width;
                [connectionController.window setFrame:frame display:YES animate:YES];
                [connectionController showWindow:self];
            
            }
            else {
                [connectionController.window orderOut:nil];
                connectionController = nil;
            }
            
            //Deselect this shit:
            [self performSelector:@selector(deselectTableRow:) withObject:[NSNumber numberWithInteger:selectedRow] afterDelay:0.2];
        }
      }
    
    }
}

- (void)deselectTableRow:(NSNumber *)aRow {
    [statusTable deselectRow:[aRow integerValue]];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDataSource
// -----------------------------------------------------------------------------
- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [((LoggerAppDelegate *)[NSApp delegate]).transports count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)rowIndex
{
	NSArray *transports = ((LoggerAppDelegate *)[NSApp delegate]).transports;
	if (rowIndex >= 0 && rowIndex < [transports count])
		return [NSNumber numberWithInteger:rowIndex];
	return nil;
}

@end
