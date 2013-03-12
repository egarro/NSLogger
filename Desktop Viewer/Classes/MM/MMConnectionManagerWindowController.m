/*
 * MMConnectionManagerWindowController.h
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010-2011 Esteban Garro <e.garro@mademediacorp.com> All Rights Reserved.
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
#import "MMConnectionManagerWindowController.h"
#import "LoggerAppDelegate.h"
#import "LoggerDocument.h"
#import "LoggerConnection.h"
#import "MMConnectionManagerTableCell.h"


@implementation MMConnectionManagerWindowController

@synthesize crashString;

- (void)dealloc
{
	[documentStatusCell release];
    [filteredListContent release];
    [allTargets release];
    
	[super dealloc];
}


- (void)awakeFromNib {
    [super awakeFromNib];
    
    [self setCrashLog];
}

- (void)windowDidLoad
{
    
    
	documentStatusCell = [[MMConnectionManagerTableCell alloc] init];
	
    [activeField setStringValue:@""];
    [disconnectedField setStringValue:@""];
    [idleField setStringValue:@""];
    [totalField setStringValue:@""];
    [wifiField setStringValue:@""];
    [cellphoneField setStringValue:@""];
    [crashField setStringValue:@""];
    
    [greenBullet setImage:[NSImage imageNamed:NSImageNameStatusAvailable]];
    [redBullet setImage:[NSImage imageNamed:NSImageNameStatusUnavailable]];
    [yellowBullet setImage:[NSImage imageNamed:NSImageNameStatusPartiallyAvailable]];
    
    filteredListContent = [[NSMutableArray alloc] init];
    allTargets = [[NSMutableArray alloc] init];
    
    isSearching = NO;

    [self fetchAllTargets];
    
	[[self window] setLevel:NSNormalWindowLevel];
}

-(void)reloadTable
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[statusTable reloadData];
        [self fetchAllTargets];
	});
}


-(void)setCrashString:(NSString *)aString {    
    crashString = aString;
    [self setCrashLog];
}


-(void)setCrashLog {
    
    if (crashString != nil ) {
        [crashLog setString:crashString];
    }
    else {
        [crashLog setString:@""];
    }
    
}


-(void)fetchAllTargets {

    NSString *selection = [dropMenu titleOfSelectedItem];
    
    [allTargets removeAllObjects];
    [allTargets addObject:@"All Targets"];
    
    for (LoggerDocument *document in ((LoggerAppDelegate *)[NSApp delegate]).documents) {
        NSString *target = [document.currentConnection.clientName uppercaseString];
        int idx = [allTargets indexOfObject:target];
        if (idx == NSNotFound) {
            [allTargets addObject:target];
        }
    }
    
    [dropMenu addItemsWithTitles:allTargets];
    [dropMenu selectItemWithTitle:selection];
    [self updateStats:nil];
}



- (IBAction)updateStats:(id)sender {

    NSString *selection = [dropMenu titleOfSelectedItem];
    if([selection isEqualToString:@"All Targets"]) {
        [searchField setStringValue:@""];
    }
    else {
        [searchField setStringValue:selection];
    }

    [self controlTextDidChange:nil];
    
    int a = 0;
    int d = 0;
    int i = 0;
    int t = 0;
    int w = 0;
    int p = 0;
    int c = 0;
    
    for (LoggerDocument *document in ((LoggerAppDelegate *)[NSApp delegate]).documents) {
        NSString *target = [document.currentConnection.clientName uppercaseString];
        
        if ([target isEqualToString:selection] ||
            [selection isEqualToString:@"All Targets"]) {
            
            switch (document.status) {
                case (DocumentStatus)active:
                    a++;
                    break;
                case (DocumentStatus)killed:
                    d++;
                    break;
                case (DocumentStatus)idle:
                    i++;
                    break;
                default:
                     NSLog(@"Client in unknown state found");
                    break;
            }
            
            if (document.currentConnection.isWiFi) {
                w++;
            }
            else {
                p++;
            }
            
            c += [document.currentConnection.clientCrashCount intValue];

            t++;
        }
    }

    [activeField setStringValue:[NSString stringWithFormat:@"%d",a]];
    [disconnectedField setStringValue:[NSString stringWithFormat:@"%d",d]];
    [idleField setStringValue:[NSString stringWithFormat:@"%d",i]];
    [totalField setStringValue:[NSString stringWithFormat:@"%d",t]];

    [wifiField setStringValue:[NSString stringWithFormat:@"%d",w]];
    [cellphoneField setStringValue:[NSString stringWithFormat:@"%d",p]];
    [crashField setStringValue:[NSString stringWithFormat:@"%d",c]];
    
    
}


// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDelegate
// -----------------------------------------------------------------------------
- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    LoggerDocument *document;
    
    if (isSearching) {
        if (row >= [filteredListContent count]) {
            return nil;
        }
        
        document = [filteredListContent objectAtIndex:row];

    }
    else {
        if (row >= [((LoggerAppDelegate *)[NSApp delegate]).documents count]) {
            return nil;
        }
        
        document = [((LoggerAppDelegate *)[NSApp delegate]).documents objectAtIndex:row];

    }
    
	
    NSString *desc = [NSString stringWithFormat:@"%@ (%@) @ %@",
                      document.currentConnection.clientName,
                      document.currentConnection.clientUDID,
                      document.currentConnection.clientMACAddress];
    NSString *status = [NSString stringWithFormat:@"%@ OS Version: %@ - App Version: %@",
                        document.currentConnection.clientDevice,
                        document.currentConnection.clientOSVersion,
                        document.currentConnection.clientVersion];
    
    
    switch (document.status) {
        case (DocumentStatus)active:
            [documentStatusCell setState:1];
            break;
        case (DocumentStatus)killed:
            [documentStatusCell setState:2];
            break;
        case (DocumentStatus)idle:
            [documentStatusCell setState:3];
            break;
        default:
            [documentStatusCell setState:4];
            break;
    }
    
    
    [documentStatusCell setDesc:desc];
    [documentStatusCell setStatus:status];
    
    
    return documentStatusCell;
    
}

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
   return NO;
}


//MM ADDITION POINT
- (IBAction)tableViewDidSelectRow:(id)sender
{
    
    if (!isSearching) {
        
    NSInteger selectedRow = [(NSTableView *)sender clickedRow];
    
    NSArray *documents = ((LoggerAppDelegate *)[NSApp delegate]).documents;
    if (selectedRow < [documents count]) {
            //Here we have to forward the click to the open the proper document!
     [(NSTableView *)sender selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
        
             LoggerDocument *selectedDocument = (LoggerDocument *)[documents objectAtIndex:selectedRow];
             if (selectedDocument.status != (DocumentStatus)killed) {
        
                 [selectedDocument makeWindowControllers];
                 [selectedDocument showMainWindow];

             }
        
            //Deselect the cell:
            [self performSelector:@selector(deselectTableRow:) withObject:[NSNumber numberWithInteger:selectedRow] afterDelay:0.2];
    }
        
    }
    else {
    
        NSInteger selectedRow = [(NSTableView *)sender clickedRow];
        
        NSArray *documents = ((LoggerAppDelegate *)[NSApp delegate]).documents;
        if (selectedRow < [filteredListContent count]) {
            //Here we have to forward the click to the open the proper document!
            [(NSTableView *)sender selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
            int d = [documents indexOfObject:[filteredListContent objectAtIndex:selectedRow]];
            
            LoggerDocument *selectedDocument = (LoggerDocument *)[documents objectAtIndex:d];
            
            if (selectedDocument.status != (DocumentStatus)killed) {
                //Create a LoggerWindow and showit!
                [selectedDocument makeWindowControllers];
                [selectedDocument showMainWindow];
            }
                        
            //Deselect the cell:
            [self performSelector:@selector(deselectTableRow:) withObject:[NSNumber numberWithInteger:selectedRow] afterDelay:0.2];
        }
    
    }

}

- (IBAction)clearCrashLog:(id)sender {

   self.crashString = @"";
    
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
    if(isSearching) return [filteredListContent count];
        
	return [((LoggerAppDelegate *)[NSApp delegate]).documents count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)rowIndex
{
    
    if (!isSearching) {
        
	NSArray *documents = ((LoggerAppDelegate *)[NSApp delegate]).documents;
	if (rowIndex >= 0 && rowIndex < [documents count])
		return [NSNumber numberWithInteger:rowIndex];
	
    }
    else {
        
        if (rowIndex >= 0 && rowIndex < [filteredListContent count])
            return [NSNumber numberWithInteger:rowIndex];
    
    }
    
    return nil;
}


// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSSearchFieldDelegate
// -----------------------------------------------------------------------------

// -------------------------------------------------------------------------------
//	controlTextDidChange:
//
//	The text in NSSearchField has changed, try to attempt type completion.
// -------------------------------------------------------------------------------
- (void)controlTextDidChange:(NSNotification *)obj
{
    isSearching = YES;
    [filteredListContent removeAllObjects];
    
    NSString *searchTerm = [searchField stringValue];
    
   	NSArray *documents = ((LoggerAppDelegate *)[NSApp delegate]).documents;
    
    for (LoggerDocument *doc in documents) {
        NSString *cellTextClean = [NSString stringWithFormat:@"%@ %@ %@",doc.currentConnection.clientName,
                                   doc.currentConnection.clientUDID, doc.currentConnection.clientMACAddress];
    
        NSRange aRange = [[cellTextClean uppercaseString] rangeOfString:[searchTerm uppercaseString]];
    
        if(aRange.length != 0) {
            [filteredListContent addObject:doc];
        }
        else if([searchTerm length] == 0) {
            [filteredListContent addObject:doc];
        }

    }
    
    
    [statusTable reloadData];
}


- (void)controlTextDidEndEditing:(NSNotification *)obj {
    
    [self performSelector:@selector(resetSearchField) withObject:nil afterDelay:0.5];
}

-(void)resetSearchField {

    [searchField setStringValue:@""];
	isSearching = NO;
    [statusTable reloadData];
    
}


@end
