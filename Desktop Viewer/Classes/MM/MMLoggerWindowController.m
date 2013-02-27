/*
 * MMLoggerWindowController.m
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2012-2013 Esteban Garro <e.garro@mademediacorp.com> All Rights Reserved.
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
#import <sys/time.h>
#import "MMLoggerWindowController.h"
#import "LoggerDetailsWindowController.h"
#import "LoggerMessageCell.h"
#import "LoggerClientInfoCell.h"
#import "LoggerMarkerCell.h"
#import "LoggerMessage.h"
#import "LoggerAppDelegate.h"
#import "LoggerCommon.h"
#import "LoggerDocument.h"
#import "LoggerSplitView.h"

@interface MMLoggerWindowController ()
@property (nonatomic, retain) NSString *info;

- (void)updateClientInfo;
- (void)refreshAllMessages:(NSArray *)selectMessages;
- (void)filterIncomingMessages:(NSArray *)messages withFilter:(NSPredicate *)aFilter tableFrameSize:(NSSize)tableFrameSize;
- (void)tileLogTable:(BOOL)forceUpdate;
- (void)rebuildRunsSubmenu;
- (void)clearRunsSubmenu;

@end

static NSString * const kNSLoggerFilterPasteboardType = @"com.florentpillet.NSLoggerFilter";
static NSArray *sXcodeFileExtensions = nil;

@implementation MMLoggerWindowController

@synthesize info;
@synthesize attachedConnection;
@synthesize messagesSelected;
@synthesize threadColumnWidth;

// -----------------------------------------------------------------------------
#pragma mark -
#pragma Standard NSWindowController stuff
// -----------------------------------------------------------------------------
- (id)initWithWindowNibName:(NSString *)nibName
{
	if ((self = [super initWithWindowNibName:nibName]) != nil)
	{
		messageFilteringQueue = dispatch_queue_create("com.florentpillet.nslogger.messageFiltering", NULL);
		displayedMessages = [[NSMutableArray alloc] initWithCapacity:4096];
		tags = [[NSMutableSet alloc] init];
		[self setShouldCloseDocument:YES];
        threadColumnWidth = DEFAULT_THREAD_COLUMN_WIDTH;
	}
	return self;
}

- (void)dealloc
{
	[detailsWindowController release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	dispatch_release(messageFilteringQueue);
	[attachedConnection release];
	[info release];
	[displayedMessages release];
	[tags release];
	[messageCell release];
	[clientInfoCell release];
	[markerCell release];
	if (lastTilingGroup)
		dispatch_release(lastTilingGroup);

    logTable.delegate = nil;
    logTable.dataSource = nil;
    
    [super dealloc];
}

- (NSUndoManager *)undoManager
{
	return [[self document] undoManager];
}

- (void)windowDidLoad
{
    if (sXcodeFileExtensions == nil) {
        sXcodeFileExtensions = [[NSArray alloc] initWithObjects:
                                @"m", @"mm", @"h", @"c", @"cp", @"cpp", @"hpp",
                                nil];
    }
    
	if ([[self window] respondsToSelector:@selector(setRestorable:)])
		[[self window] setRestorable:NO];

	messageCell = [[LoggerMessageCell alloc] init];
	clientInfoCell = [[LoggerClientInfoCell alloc] init];
	markerCell = [[LoggerMarkerCell alloc] init];

	[logTable setIntercellSpacing:NSMakeSize(0,0)];
	[logTable setTarget:self];
	[logTable setDoubleAction:@selector(logCellDoubleClicked:)];

	[logTable registerForDraggedTypes:[NSArray arrayWithObject:NSPasteboardTypeString]];
	[logTable setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
	[logTable setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];

	[logTable sizeToFit];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(applyFontChanges)
												 name:kMessageAttributesChangedNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(tileLogTableNotification:)
												 name:@"TileLogTableNotification"
											   object:nil];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
	if ([[self document] fileURL] != nil)
		return displayName;
	if (attachedConnection.connected)
		return [attachedConnection clientAppDescription];
	return [NSString stringWithFormat:NSLocalizedString(@"%@ (disconnected)", @""),
			[attachedConnection clientDescription]];
}

- (void)updateClientInfo
{
	// Update the source label
	assert([NSThread isMainThread]);
	[self synchronizeWindowTitleWithDocumentName];
}

- (void)updateMenuBar:(BOOL)documentIsFront
{
	if (documentIsFront)
	{
		[self rebuildRunsSubmenu];
	}
	else
	{
		[self clearRunsSubmenu];
	}
}

- (void)tileLogTableMessages:(NSArray *)messages
					withSize:(NSSize)tableSize
				 forceUpdate:(BOOL)forceUpdate
					   group:(dispatch_group_t)group
{
	NSMutableArray *updatedMessages = [[NSMutableArray alloc] initWithCapacity:[messages count]];
	for (LoggerMessage *msg in messages)
	{
		// detect cancellation
		if (group != NULL && dispatch_get_context(group) == NULL)
			break;

		// compute size
		NSSize cachedSize = msg.cachedCellSize;
		if (forceUpdate || cachedSize.width != tableSize.width)
		{
			CGFloat cachedHeight = cachedSize.height;
			CGFloat newHeight = cachedHeight;
			if (forceUpdate)
				msg.cachedCellSize = NSZeroSize;
			switch (msg.type)
			{
				case LOGMSG_TYPE_LOG:
				case LOGMSG_TYPE_BLOCKSTART:
				case LOGMSG_TYPE_BLOCKEND:
					newHeight = [LoggerMessageCell heightForCellWithMessage:msg threadColumnWidth:threadColumnWidth maxSize:tableSize showFunctionNames:showFunctionNames];
					break;
				case LOGMSG_TYPE_CLIENTINFO:
				case LOGMSG_TYPE_DISCONNECT:
					newHeight = [LoggerClientInfoCell heightForCellWithMessage:msg threadColumnWidth:threadColumnWidth maxSize:tableSize showFunctionNames:showFunctionNames];
					break;
				case LOGMSG_TYPE_MARK:
					newHeight = [LoggerMarkerCell heightForCellWithMessage:msg threadColumnWidth:threadColumnWidth maxSize:tableSize showFunctionNames:showFunctionNames];
					break;
			}
			if (newHeight != cachedHeight)
				[updatedMessages addObject:msg];
			else if (forceUpdate)
				msg.cachedCellSize = cachedSize;
		}
	}
	if ([updatedMessages count])
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			if (group == NULL || dispatch_get_context(group) != NULL)
			{
				NSMutableIndexSet *set = [[NSMutableIndexSet alloc] init];
				for (LoggerMessage *msg in updatedMessages)
				{
					NSUInteger pos = [displayedMessages indexOfObjectIdenticalTo:msg];
					if (pos == NSNotFound || pos > lastMessageRow)
						break;
					[set addIndex:pos];
				}
				if ([set count])
					[logTable noteHeightOfRowsWithIndexesChanged:set];
				[set release];
			}
		});
	}
	[updatedMessages release];
}

- (void)tileLogTable:(BOOL)forceUpdate
{
	// tile the visible rows (and a bit more) first, then tile all the rest
	// this gives us a better perceived speed
	NSSize tableSize = [logTable frame].size;
	NSRect r = [[logTable superview] convertRect:[[logTable superview] bounds] toView:logTable];
	NSRange visibleRows = [logTable rowsInRect:r];
	visibleRows.location = MAX((int)0, (int)visibleRows.location - 10);
	visibleRows.length = MIN(visibleRows.location + visibleRows.length + 10, [displayedMessages count] - visibleRows.location);
	if (visibleRows.length)
	{
		[self tileLogTableMessages:[displayedMessages subarrayWithRange:visibleRows]
						  withSize:tableSize
					   forceUpdate:forceUpdate
							 group:NULL];
	}
	
	// cancel previous tiling group
	if (lastTilingGroup != NULL)
	{
		dispatch_set_context(lastTilingGroup, NULL);
		dispatch_release(lastTilingGroup);
	}
	
	// create new group, set it a non-NULL context to indicate that it is running
	lastTilingGroup = dispatch_group_create();
	dispatch_set_context(lastTilingGroup, "running");
	
	// perform layout in chunks in the background
	for (NSUInteger i = 0; i < [displayedMessages count]; i += 1024)
	{
		// tiling is executed on a parallel queue, and checks for cancellation
		// by looking at its group's context object 
		NSRange range = NSMakeRange(i, MIN(1024, [displayedMessages count] - i));
		if (range.length > 0)
		{
			NSArray *subArray = [displayedMessages subarrayWithRange:range];
			dispatch_group_t group = lastTilingGroup;		// careful with self dereference, could use the wrong group at run time, hence the copy here
			dispatch_group_async(group,
								 dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
								 ^{
									 [self tileLogTableMessages:subArray
													   withSize:tableSize
													forceUpdate:forceUpdate
														  group:group];
								 });
		}
	}
}

- (void)tileLogTableNotification:(NSNotification *)note
{
	[self tileLogTable:NO];
}

- (void)applyFontChanges
{
	[self tileLogTable:YES];
	[logTable reloadData];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Support for multiple runs in same window
// -----------------------------------------------------------------------------
- (void)rebuildRunsSubmenu
{
	LoggerDocument *doc = (LoggerDocument *)self.document;
	NSMenuItem *runsSubmenu = [[[[NSApp mainMenu] itemWithTag:VIEW_MENU_ITEM_TAG] submenu] itemWithTag:VIEW_MENU_SWITCH_TO_RUN_TAG];
	NSArray *runsNames = [doc attachedLogsPopupNames];
	NSMenu *menu = [runsSubmenu submenu];
	[menu removeAllItems];
	NSInteger i = 0;
	NSInteger currentRun = [[doc indexOfCurrentVisibleLog] integerValue];
	for (NSString *name in runsNames)
	{
		NSMenuItem *runItem = [[NSMenuItem alloc] initWithTitle:name
														 action:@selector(selectRun:)
												  keyEquivalent:@""];
		if (i == currentRun)
			[runItem setState:NSOnState];
		[runItem setTag:i++];
		[runItem setTarget:self];
		[menu addItem:runItem];
		[runItem release];
	}
}

- (void)clearRunsSubmenu
{
	NSMenuItem *runsSubmenu = [[[[NSApp mainMenu] itemWithTag:VIEW_MENU_ITEM_TAG] submenu] itemWithTag:VIEW_MENU_SWITCH_TO_RUN_TAG];
	NSMenu *menu = [runsSubmenu submenu];
	[menu removeAllItems];
	NSMenuItem *dummyItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Run Log", @"") action:nil keyEquivalent:@""];
	[dummyItem setEnabled:NO];
	[menu addItem:dummyItem];
	[dummyItem release];
}

- (void)selectRun:(NSMenuItem *)anItem
{
	((LoggerDocument *)self.document).indexOfCurrentVisibleLog = [NSNumber numberWithInteger:[anItem tag]];
}



// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Per-Application settings
// -----------------------------------------------------------------------------
- (NSDictionary *)settingsForClientApplication
{
	NSString *clientAppIdentifier = [attachedConnection clientName];
	if (![clientAppIdentifier length])
		return nil;

	NSDictionary *clientSettings = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefClientApplicationSettings];
	if (clientSettings == nil)
		return [NSDictionary dictionary];
	
	NSDictionary *appSettings = [clientSettings objectForKey:clientAppIdentifier];
	if (appSettings == nil)
		return [NSDictionary dictionary];
	return appSettings;
}

- (void)saveSettingsForClientApplication:(NSDictionary *)newSettings
{
	NSString *clientAppIdentifier = [attachedConnection clientName];
	if (![clientAppIdentifier length])
		return;
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *clientSettings = [[[ud objectForKey:kPrefClientApplicationSettings] mutableCopy] autorelease];
	if (clientSettings == nil)
		clientSettings = [NSMutableDictionary dictionary];
	[clientSettings setObject:newSettings forKey:clientAppIdentifier];
	[ud setObject:clientSettings forKey:kPrefClientApplicationSettings];
}

- (void)setSettingForClientApplication:(id)aValue forKey:(NSString *)aKey
{
	NSMutableDictionary *dict = [[self settingsForClientApplication] mutableCopy];
	[dict setObject:aValue forKey:aKey];
	[self saveSettingsForClientApplication:dict];
	[dict release];
}



// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Splitview delegate
// -----------------------------------------------------------------------------
- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
//	tableNeedsTiling = YES;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Window delegate
// -----------------------------------------------------------------------------
- (void)windowDidResize:(NSNotification *)notification
{
	if (![[self window] inLiveResize])
		[self tileLogTable:NO];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
	[self tileLogTable:NO];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
	[self updateMenuBar:YES];

}

- (void)windowDidResignMain:(NSNotification *)notification
{
	[self updateMenuBar:NO];

}

- (BOOL)windowShouldClose:(id)sender {
    
    //MM ADDITION POINT:
    //Prevent people from closing the Window when the Connection Manager is on:
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kPrefUseConnectionManager]) {
        return YES;
    }
    else {
        //Hide the window, but don't destroy it!
        [self.window orderOut:nil];
        return NO;
    }
}

//-(void)windowWillClose:(NSNotification *)notification {
//
//    NSLog(@"Window will close!");
//}


// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Table management
// -----------------------------------------------------------------------------
- (void)messagesAppendedToTable
{
	assert([NSThread isMainThread]);
	if (attachedConnection.connected)
	{
		NSRect r = [[logTable superview] convertRect:[[logTable superview] bounds] toView:logTable];
		NSRange visibleRows = [logTable rowsInRect:r];
		BOOL lastVisible = (visibleRows.location == NSNotFound ||
							visibleRows.length == 0 ||
							(visibleRows.location + visibleRows.length) >= lastMessageRow);
		[logTable noteNumberOfRowsChanged];
		if (lastVisible)
			[logTable scrollRowToVisible:[displayedMessages count] - 1];
	}
	else
	{
		[logTable noteNumberOfRowsChanged];
	}
	lastMessageRow = [displayedMessages count];
	self.info = [NSString stringWithFormat:NSLocalizedString(@"%u messages", @""), [displayedMessages count]];
}

- (void)appendMessagesToTable:(NSArray *)messages
{
	assert([NSThread isMainThread]);
	[displayedMessages addObjectsFromArray:messages];

	// schedule a table reload. Do this asynchronously (and cancellable-y) so we can limit the
	// number of reload requests in case of high load
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(messagesAppendedToTable) object:nil];
	[self performSelector:@selector(messagesAppendedToTable) withObject:nil afterDelay:0];
}


- (void)xedFile:(NSString *)path line:(NSString *)line { 
    id args = [NSArray arrayWithObjects:
               @"-l",
               line,
               path,
               nil];
    // NSLog(@"Args %@", args);
    [NSTask launchedTaskWithLaunchPath:[[NSBundle mainBundle] pathForResource:@"xedReplacement.sh" ofType:nil]
                             arguments:args];
}

- (void)logCellDoubleClicked:(id)sender
{
	// Added in v1.1: alt-double click opens the source file if it was defined in the log
	// and the file is found
	NSEvent *event = [NSApp currentEvent];
	if ([event clickCount] > 1 && ([NSEvent modifierFlags] & NSAlternateKeyMask) != 0)
	{
		NSInteger row = [logTable selectedRow];
		if (row >= 0 && row < [displayedMessages count])
		{
			LoggerMessage *msg = [displayedMessages objectAtIndex:row];
			NSString *filename = msg.filename;
			if ([filename length])
			{
				NSFileManager *fm = [[NSFileManager alloc] init];
				if ([fm fileExistsAtPath:filename])
				{
					// If the file is .h, .m, .c, .cpp, .h, .hpp: open the file
					// using xed. Otherwise, open the file with the Finder. We really don't
					// know which IDE the user is running if it's not Xcode
					// (when logging from Android, could be IntelliJ or Eclipse)
					NSString *extension = [filename pathExtension];
					BOOL useXcode = NO;
                    //if ([fm fileExistsAtPath:@"/usr/bin/xed"])
                    //{
                    for (NSString *ext in sXcodeFileExtensions)
                    {
                        if ([ext caseInsensitiveCompare:extension] == NSOrderedSame)
                        {
                            useXcode = YES;
                            break;
                        }
                    }
                    //}
					if (useXcode)
					{                        
                        [self xedFile:filename 
                                 line:[NSString stringWithFormat:@"%d", MAX(0, msg.lineNumber) + 1]];
					}
					else
					{
						[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:filename]];
					}
				}
			}
		}
		return;
	}
	[self openDetailsWindow:sender];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filtering
// -----------------------------------------------------------------------------
- (void)refreshAllMessages:(NSArray *)selectedMessages
{
    NSLog(@"refreshAllMessages:");
	assert([NSThread isMainThread]);
	@synchronized (attachedConnection.messages)
	{
		BOOL quickFilterWasFirstResponder = NO;
		id messageToMakeVisible = [selectedMessages objectAtIndex:0];
		if (messageToMakeVisible == nil)
		{
			// Remember the currently selected messages
			NSIndexSet *selectedRows = [logTable selectedRowIndexes];
			if ([selectedRows count])
				selectedMessages = [displayedMessages objectsAtIndexes:selectedRows];
            
			NSRect r = [[logTable superview] convertRect:[[logTable superview] bounds] toView:logTable];
			NSRange visibleRows = [logTable rowsInRect:r];
			if (visibleRows.length != 0)
			{
				NSIndexSet *selectedVisible = [selectedRows indexesInRange:visibleRows options:0 passingTest:^(NSUInteger idx, BOOL *stop){return YES;}];
				if ([selectedVisible count])
					messageToMakeVisible = [displayedMessages objectAtIndex:[selectedVisible firstIndex]];
				else
					messageToMakeVisible = [displayedMessages objectAtIndex:visibleRows.location];
			}
		}
        
		LoggerConnection *theConnection = attachedConnection;
        
		NSSize tableFrameSize = [logTable frame].size;
		NSUInteger numMessages = [attachedConnection.messages count];
		for (int i = 0; i < numMessages;)
		{
			if (i == 0)
			{
				dispatch_async(messageFilteringQueue, ^{
					dispatch_async(dispatch_get_main_queue(), ^{
						lastMessageRow = 0;
						[displayedMessages removeAllObjects];
						[logTable reloadData];
						self.info = NSLocalizedString(@"No message", @"");
					});
				});
			}
			NSUInteger length = MIN(4096, numMessages - i);
			if (length)
			{
				NSPredicate *aFilter = [self alwaysVisibleEntriesPredicate];
				NSArray *subArray = [attachedConnection.messages subarrayWithRange:NSMakeRange(i, length)];
				dispatch_async(messageFilteringQueue, ^{
					// Check that the connection didn't change
					if (attachedConnection == theConnection)
						[self filterIncomingMessages:subArray withFilter:aFilter tableFrameSize:tableFrameSize];
				});
			}
			i += length;
		}
        
		// Stuff we want to do only when filtering is complete. To do this, we enqueue
		// one more operation to the message filtering queue, with the only goal of
		// being executed only at the end of the filtering process
		dispatch_async(messageFilteringQueue, ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				// if the connection changed since the last refreshAll call, stop now
				if (attachedConnection == theConnection)		// note that block retains self, not self.attachedConnection.
				{
					if (lastMessageRow < [displayedMessages count])
					{
						// perform table updates now, so we can properly reselect afterwards
						[NSObject cancelPreviousPerformRequestsWithTarget:self
																 selector:@selector(messagesAppendedToTable)
																   object:nil];
						[self messagesAppendedToTable];
					}
					
					if ([selectedMessages count])
					{
						// If there were selected rows, try to reselect them
						NSMutableIndexSet *newSelectionIndexes = [[NSMutableIndexSet alloc] init];
						for (id msg in selectedMessages)
						{
							NSInteger msgIndex = [displayedMessages indexOfObjectIdenticalTo:msg];
							if (msgIndex != NSNotFound)
								[newSelectionIndexes addIndex:(NSUInteger)msgIndex];
						}
						if ([newSelectionIndexes count])
						{
							[logTable selectRowIndexes:newSelectionIndexes byExtendingSelection:NO];
							if (!quickFilterWasFirstResponder)
								[[self window] makeFirstResponder:logTable];
						}
						[newSelectionIndexes release];
					}
					
					if (messageToMakeVisible != nil)
					{
						// Restore the logical location in the message flow, to keep the user
						// in-context
						NSUInteger msgIndex;
						id msg = messageToMakeVisible;
						@synchronized(attachedConnection.messages)
						{
							while ((msgIndex = [displayedMessages indexOfObjectIdenticalTo:msg]) == NSNotFound)
							{
								NSUInteger where = [attachedConnection.messages indexOfObjectIdenticalTo:msg];
								if (where == NSNotFound)
									break;
								if (where == 0)
								{
									msgIndex = 0;
									break;
								}
								else
									msg = [attachedConnection.messages objectAtIndex:where-1];
							}
							if (msgIndex != NSNotFound)
								[logTable scrollRowToVisible:msgIndex];
						}
					}
					
					
				}
				initialRefreshDone = YES;
			});
		});
	}
}

- (NSPredicate *)alwaysVisibleEntriesPredicate
{
    NSLog(@"alwaysVisibleEntriesPredicate");
	NSExpression *lhs = [NSExpression expressionForKeyPath:@"type"];
	NSExpression *rhs = [NSExpression expressionForConstantValue:[NSSet setWithObjects:
																  [NSNumber numberWithInteger:LOGMSG_TYPE_MARK],
																  [NSNumber numberWithInteger:LOGMSG_TYPE_CLIENTINFO],
																  [NSNumber numberWithInteger:LOGMSG_TYPE_DISCONNECT],
																  nil]];
	NSPredicate *p = [NSComparisonPredicate predicateWithLeftExpression:lhs
											  rightExpression:rhs
													 modifier:NSDirectPredicateModifier
														 type:NSInPredicateOperatorType
													  options:0];
    
    NSPredicate *resp = [NSCompoundPredicate orPredicateWithSubpredicates:[NSArray arrayWithObjects:p, [NSPredicate predicateWithValue:YES], nil]];
    
    return resp;
}

- (void)filterIncomingMessages:(NSArray *)messages
{
    NSLog(@"FILTER Incoming Messages:");
    
    NSPredicate *filterPredicate = [NSPredicate predicateWithValue:YES];
    
	assert([NSThread isMainThread]);
	NSPredicate *aFilter = filterPredicate;		// catch value now rather than dereference it from self later
	NSSize tableFrameSize = [logTable frame].size;
	dispatch_async(messageFilteringQueue, ^{
		[self filterIncomingMessages:(NSArray *)messages withFilter:aFilter tableFrameSize:tableFrameSize];
	});
}

- (void)filterIncomingMessages:(NSArray *)messages
					withFilter:(NSPredicate *)aFilter
				tableFrameSize:(NSSize)tableFrameSize
{
    
    NSLog(@"filterIncomingMessages:withFilter:tableFrameSize:");
    
	// collect all tags
	NSArray *msgTags = [messages valueForKeyPath:@"@distinctUnionOfObjects.tag"];
    
	// find out which messages we want to keep. Executed on the message filtering queue
	NSArray *filteredMessages = [messages filteredArrayUsingPredicate:aFilter];
	if ([filteredMessages count])
	{
		[self tileLogTableMessages:filteredMessages withSize:tableFrameSize forceUpdate:NO group:NULL];
		LoggerConnection *theConnection = attachedConnection;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (attachedConnection == theConnection)
			{
				[self appendMessagesToTable:filteredMessages];
				//[self addTags:msgTags];
			}
		});
	}
}


// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Properties and bindings
// -----------------------------------------------------------------------------
- (void)setAttachedConnection:(LoggerConnection *)aConnection
{
	assert([NSThread isMainThread]);

	if (attachedConnection != nil)
	{
		// Completely clear log table
		[logTable deselectAll:self];
		lastMessageRow = 0;
		[displayedMessages removeAllObjects];
		self.info = NSLocalizedString(@"No message", @"");
		[logTable reloadData];


		// Cancel pending tasks
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshAllMessages:) object:nil];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(messagesAppendedToTable) object:nil];
		if (lastTilingGroup != NULL)
		{
			dispatch_set_context(lastTilingGroup, NULL);
			dispatch_release(lastTilingGroup);
			lastTilingGroup = NULL;
		}
		
		// Detach previous connection
		attachedConnection.attachedToWindow = NO;
		[attachedConnection release];
		attachedConnection = nil;
	}
	if (aConnection != nil)
	{
		attachedConnection = [aConnection retain];
		attachedConnection.attachedToWindow = YES;
		//dispatch_async(dispatch_get_main_queue(), ^{
			initialRefreshDone = NO;
			[self updateClientInfo];
			[self rebuildRunsSubmenu];
			[self refreshAllMessages:nil];
		//});
	}
}

- (NSNumber *)shouldEnableRunsPopup
{
	NSUInteger numRuns = [((LoggerDocument *)[self document]).attachedLogs count];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kPrefKeepMultipleRuns] && numRuns <= 1)
		return (id)kCFBooleanFalse;
	return (id)kCFBooleanTrue;
}


- (void)setShowFunctionNames:(NSNumber *)value
{
	BOOL b = [value boolValue];
	if (b != showFunctionNames)
	{
		[self willChangeValueForKey:@"showFunctionNames"];
		showFunctionNames = b;
		[self tileLogTable:YES];
		dispatch_async(dispatch_get_main_queue(), ^{
			[logTable reloadData];
		});
		[self didChangeValueForKey:@"showFunctionNames"];

		dispatch_async(dispatch_get_main_queue(), ^{
			[self setSettingForClientApplication:value forKey:@"showFunctionNames"];
		});
	}
}

- (NSNumber *)showFunctionNames
{
	return [NSNumber numberWithBool:showFunctionNames];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark LoggerConnectionDelegate
// -----------------------------------------------------------------------------
- (void)connection:(LoggerConnection *)theConnection
didReceiveMessages:(NSArray *)theMessages
			 range:(NSRange)rangeInMessagesList
{
	// We need to hop thru the main thread to have a recent and stable copy of the filter string and current filter
	dispatch_async(dispatch_get_main_queue(), ^{
		if (initialRefreshDone)
			[self filterIncomingMessages:theMessages];
	});
}

- (void)remoteDisconnected:(LoggerConnection *)theConnection
{
	// we always get called on the main thread
	[self updateClientInfo];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark KVO / Bindings
// -----------------------------------------------------------------------------
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == attachedConnection)
	{
		if ([keyPath isEqualToString:@"clientIDReceived"])
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self updateClientInfo];
				
			});			
		}
	}
	
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDelegate
// -----------------------------------------------------------------------------
- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView == logTable && row >= 0 && row < [displayedMessages count])
	{
		LoggerMessage *msg = [displayedMessages objectAtIndex:row];
		switch (msg.type)
		{
			case LOGMSG_TYPE_LOG:
			case LOGMSG_TYPE_BLOCKSTART:
			case LOGMSG_TYPE_BLOCKEND:
				return messageCell;
			case LOGMSG_TYPE_CLIENTINFO:
			case LOGMSG_TYPE_DISCONNECT:
				return clientInfoCell;
			case LOGMSG_TYPE_MARK:
				return markerCell;
			default:
				assert(false);
				break;
		}
	}
	return nil;
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if (aTableView == logTable && rowIndex >= 0 && rowIndex < [displayedMessages count])
	{
		// setup the message to be displayed
		LoggerMessageCell *cell = (LoggerMessageCell *)aCell;
		cell.message = [displayedMessages objectAtIndex:rowIndex];
		cell.shouldShowFunctionNames = showFunctionNames;

		// if previous message is a Mark, go back a bit more to get the real previous message
		// if previous message is ClientInfo, don't use it.
		NSInteger idx = rowIndex - 1;
		LoggerMessage *prev = nil;
		while (prev == nil && idx >= 0)
		{
			prev = [displayedMessages objectAtIndex:idx--];
			if (prev.type == LOGMSG_TYPE_CLIENTINFO || prev.type == LOGMSG_TYPE_MARK)
				prev = nil;
		} 
		
		cell.previousMessage = prev;
	}
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	assert([NSThread isMainThread]);
	if (tableView == logTable && row >= 0 && row < [displayedMessages count])
	{
		// use only cached sizes
		LoggerMessage *message = [displayedMessages objectAtIndex:row];
		NSSize cachedSize = message.cachedCellSize;
		if (cachedSize.height)
			return cachedSize.height;
	}
	return [tableView rowHeight];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([aNotification object] == logTable)
	{
		self.messagesSelected = ([logTable selectedRow] >= 0);
		if (messagesSelected && detailsWindowController != nil && [[detailsWindowController window] isVisible])
			[detailsWindowController setMessages:[displayedMessages objectsAtIndexes:[logTable selectedRowIndexes]]];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDataSource
// -----------------------------------------------------------------------------
- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [displayedMessages count];
}

- (id)tableView:(NSTableView *)tableView
	objectValueForTableColumn:(NSTableColumn *)tableColumn
	row:(int)rowIndex
{
	if (rowIndex >= 0 && rowIndex < [displayedMessages count])
		return [displayedMessages objectAtIndex:rowIndex];
	return nil;
}

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	if (tv == logTable)
	{
		NSArray *draggedMessages = [displayedMessages objectsAtIndexes:rowIndexes];
		NSMutableString *string = [[NSMutableString alloc] initWithCapacity:[draggedMessages count] * 128];
		for (LoggerMessage *msg in draggedMessages)
			[string appendString:[msg textRepresentation]];
		[pboard writeObjects:[NSArray arrayWithObject:string]];
		[string release];
		return YES;
	}

	return NO;
}

- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)dragInfo proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
	
	return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tv
	   acceptDrop:(id <NSDraggingInfo>)dragInfo
			  row:(NSInteger)row
	dropOperation:(NSTableViewDropOperation)operation
{
	BOOL added = NO;
	
	if (added)
		[(LoggerAppDelegate *)[NSApp delegate] saveFiltersDefinition];
	return added;
}




// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark User Interface Items Validation
// -----------------------------------------------------------------------------
- (BOOL)validateUserInterfaceItem:(id)anItem
{
	SEL action = [anItem action];
	if (action == @selector(deleteMark:))
	{
		NSInteger rowIndex = [logTable selectedRow];
		if (rowIndex >= 0 && rowIndex < (NSInteger)[displayedMessages count])
		{
			LoggerMessage *markMessage = [displayedMessages objectAtIndex:(NSUInteger)rowIndex];
			return (markMessage.type == LOGMSG_TYPE_MARK);
		}
		return NO;
	}
	else if (action == @selector(clearCurrentLog:))
	{
		// Allow "Clear Log" only if the log was not restored from save
		if (attachedConnection == nil || attachedConnection.restoredFromSave)
			return NO;
	}
	else if (action == @selector(clearAllLogs:))
	{
		// Allow "Clear All Run Logs" only if the log was not restored from save
		// and there are multiple run logs
		if (attachedConnection == nil || attachedConnection.restoredFromSave || [((LoggerDocument *)[self document]).attachedLogs count] <= 1)
			return NO;
	}
	return YES;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Support for clear current // all logs
// -----------------------------------------------------------------------------
- (BOOL)canClearCurrentLog
{
	return (attachedConnection != nil && !attachedConnection.restoredFromSave);
}

- (IBAction)clearCurrentLog:(id)sender
{
	[(LoggerDocument *)[self document] clearLogs:NO];
}

- (BOOL)canClearAllLogs
{
	return (attachedConnection != nil && !attachedConnection.restoredFromSave && [((LoggerDocument *)[self document]).attachedLogs count] > 1);
}

- (IBAction)clearAllLogs:(id)sender
{
	[(LoggerDocument *)[self document] clearLogs:YES];
}

#pragma mark - 
#pragma mark - Collapsing Taskbar

- (IBAction)collapseTaskbar:(id)sender{
    
    NSMenuItem *hideShowButton = [[[[NSApp mainMenu] itemWithTag:VIEW_MENU_ITEM_TAG] submenu] itemWithTag:TOOLS_MENU_HIDE_SHOW_TOOLBAR];
    
    if (![splitView collapsibleSubviewCollapsed]) {
        [hideShowButton setTitle:NSLocalizedString(@"Show Taskbar", @"Show Taskbar")];
    }
    else{
        [hideShowButton setTitle:NSLocalizedString(@"Hide Taskbar", @"Hide Taskbar")];
    }

    [splitView toggleCollapse:nil];

}

@end

