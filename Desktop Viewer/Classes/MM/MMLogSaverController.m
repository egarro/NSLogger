/*
 * MMLogSaverController.m
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
#import "MMLogSaverController.h"
#import "LoggerMessage.h"
#import "LoggerAppDelegate.h"
#import "LoggerCommon.h"
#import "LoggerDocument.h"

@interface MMLogSaverController ()

- (void)refreshAllMessages:(NSArray *)selectMessages;
- (void)filterIncomingMessages:(NSArray *)messages withFilter:(NSPredicate *)aFilter tableFrameSize:(NSSize)tableFrameSize;
- (void)tileLogTable:(BOOL)forceUpdate;

@end

static NSString * const kNSLoggerFilterPasteboardType = @"com.florentpillet.NSLoggerFilter";

@implementation MMLogSaverController

@synthesize threadColumnWidth;
@synthesize attachedConnection;
@synthesize delegate;


// -----------------------------------------------------------------------------
#pragma mark -
#pragma Standard NSWindowController stuff
// -----------------------------------------------------------------------------
- (id)init
{
	if ((self = [super init]) != nil)
	{
		messageFilteringQueue = dispatch_queue_create("com.florentpillet.nslogger.messageFiltering", NULL);
		displayedMessages = [[NSMutableArray alloc] initWithCapacity:4096];
        threadColumnWidth = 85.0f;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tileLogTableNotification:)
                                                     name:@"TileLogTableNotification"
                                                   object:nil];
	}
	return self;
}

- (void)dealloc
{
    
    NSLog(@"dealloc MMLogSaverController"); 
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	dispatch_release(messageFilteringQueue);
	[attachedConnection release];
	[displayedMessages release];

	if (lastTilingGroup)
		dispatch_release(lastTilingGroup);
    
    [super dealloc];
}



- (void)tileLogTableMessages:(NSArray *)messages
					withSize:(NSSize)tableSize
				 forceUpdate:(BOOL)forceUpdate
					   group:(dispatch_group_t)group
{
	
    //NSLog(@"tileLogTableMessages: %@ - withSize: %.1f x %.1f - forceUpdate: %@ - group: %@",messages,tableSize.width, tableSize.height, forceUpdate ? @"YES" : @"NO" , group);
    
    NSMutableArray *updatedMessages = [[NSMutableArray alloc] initWithCapacity:[messages count]];
	for (LoggerMessage *msg in messages)
	{
		// detect cancellation
		if (group != NULL && dispatch_get_context(group) == NULL)
			break;

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

				[set release];
			}
		});
	}
	[updatedMessages release];
}

- (void)tileLogTable:(BOOL)forceUpdate
{
    NSLog(@"tileLogTable:");
	// tile the visible rows (and a bit more) first, then tile all the rest
	// this gives us a better perceived speed

    NSSize tableSize = NSZeroSize;
	
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
    NSLog(@"tileLogTableNotification:");
	[self tileLogTable:NO];
}



// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Per-Application settings
// -----------------------------------------------------------------------------
- (NSDictionary *)settingsForClientApplication
{
    NSLog(@"settingsForClientApplication");
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
    NSLog(@"saveSettingsForClientApplication:");
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
    NSLog(@"setSettingForClientApplication:forKey:");
	NSMutableDictionary *dict = [[self settingsForClientApplication] mutableCopy];
	[dict setObject:aValue forKey:aKey];
	[self saveSettingsForClientApplication:dict];
	[dict release];
}



// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Table management
// -----------------------------------------------------------------------------
- (void)messagesAppendedToTable
{
	assert([NSThread isMainThread]);
	lastMessageRow = [displayedMessages count];

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
		id messageToMakeVisible = [selectedMessages objectAtIndex:0];
        
		LoggerConnection *theConnection = attachedConnection;
        
        NSSize tableFrameSize = NSZeroSize;
        
		NSUInteger numMessages = [attachedConnection.messages count];
		for (int i = 0; i < numMessages;)
		{
			if (i == 0)
			{
				dispatch_async(messageFilteringQueue, ^{
					dispatch_async(dispatch_get_main_queue(), ^{
						lastMessageRow = 0;
						[displayedMessages removeAllObjects];
						//[logTable reloadData];
					});
				});
			}
			NSUInteger length = MIN(4096, numMessages - i);
			if (length)
			{
				NSPredicate *aFilter = [NSPredicate predicateWithValue:YES];
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

                            
						}
					}
					
					
				}
				initialRefreshDone = YES;
			});
		});
	}
}


- (void)filterIncomingMessages:(NSArray *)messages
{
    //NSLog(@"FILTER Incoming Messages:");
    
    NSPredicate *filterPredicate = [NSPredicate predicateWithValue:YES];
    
	assert([NSThread isMainThread]);
	NSPredicate *aFilter = filterPredicate;		// catch value now rather than dereference it from self later
	//NSSize tableFrameSize = [logTable frame].size;
	dispatch_async(messageFilteringQueue, ^{
        [self filterIncomingMessages:(NSArray *)messages withFilter:aFilter tableFrameSize:NSZeroSize];

	});
}

- (void)filterIncomingMessages:(NSArray *)messages
					withFilter:(NSPredicate *)aFilter
				tableFrameSize:(NSSize)tableFrameSize
{
    
    //NSLog(@"filterIncomingMessages:withFilter:tableFrameSize:");
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
		//[logTable deselectAll:self];
		lastMessageRow = 0;
		[displayedMessages removeAllObjects];
		//[logTable reloadData];


		// Cancel pending tasks
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshAllMessages:) object:nil];
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
			[self refreshAllMessages:nil];
		//});
	}
}

- (NSNumber *)shouldEnableRunsPopup
{
	return [NSNumber numberWithBool:NO];
}



- (NSNumber *)showFunctionNames
{
	NSLog(@"showFunctionNames");

	return [NSNumber numberWithBool:YES];
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
    if ([self.delegate respondsToSelector:@selector(updateClientInfo)]) {
        [self.delegate updateClientInfo];
    }
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
				
                if ([self.delegate respondsToSelector:@selector(updateClientInfo)]) {
                    [self.delegate updateClientInfo];
                }
				
			});			
		}
	}
	
}


// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark User Interface Items Validation
// -----------------------------------------------------------------------------
- (BOOL)validateUserInterfaceItem:(id)anItem
{
	SEL action = [anItem action];
    if (action == @selector(clearCurrentLog))
	{
		// Allow "Clear Log" only if the log was not restored from save
		if (attachedConnection == nil || attachedConnection.restoredFromSave)
			return NO;
	}
	else if (action == @selector(clearAllLogs))
	{
		// Allow "Clear All Run Logs" only if the log was not restored from save
		// and there are multiple run logs
		if (attachedConnection == nil || attachedConnection.restoredFromSave)
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
	return YES;
}

- (void)clearCurrentLog
{
    if ([self.delegate respondsToSelector:@selector(clearLogs)]) {
        [self.delegate clearLogs];
    }

}

- (BOOL)canClearAllLogs
{
	return YES;
}

- (void)clearAllLogs
{
    if ([self.delegate respondsToSelector:@selector(clearLogs)]) {
        [self.delegate clearLogs];
    }
}


@end

