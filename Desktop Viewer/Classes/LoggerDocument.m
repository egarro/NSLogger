/*
 * LoggerDocument.h
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
#import "LoggerDocument.h"
#import "LoggerWindowController.h"
#import "LoggerTransport.h"
#import "LoggerCommon.h"
#import "LoggerConnection.h"
#import "LoggerNativeMessage.h"
#import "LoggerAppDelegate.h"

#define SAVING_MESSAGES_INTERVAL 40
//#define IDLE_DEFINITION_TIME 600  //10 Minutes
#define IDLE_DEFINITION_TIME 30  //30 Seconds

@implementation LoggerDocument

@synthesize attachedLogs;
@synthesize tag, active, disconnected, idle;
@synthesize currentConnection;

@dynamic indexOfCurrentVisibleLog;

+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)typeName
{
	return YES;
}

- (id)init
{
	if ((self = [super init]) != nil)
	{
		attachedLogs = [[NSMutableArray alloc] init];
	}
	return self;
}

- (id)initWithConnection:(LoggerConnection *)aConnection
{
	if ((self = [super init]) != nil)
	{
		attachedLogs = [[NSMutableArray alloc] init];
		aConnection.delegate = self;
		[attachedLogs addObject:aConnection];
		currentConnection = aConnection;
        messageCounter = 0;
        idleTimer = nil;
	}
	return self;
}

- (void)close
{
	// since delegate is retained, we need to set it to nil
	[attachedLogs makeObjectsPerformSelector:@selector(setDelegate:) withObject:nil];
	[super close];
}

- (BOOL)isDocumentEdited {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPrefCloseWithoutSaving]) {
        /* Don't bother asking, I don't want to save the logs 99% of the time. */
        return NO;
    }
    return [super isDocumentEdited];
}

- (void)selectRun:(NSInteger)runIndex
{
	if (![attachedLogs count])
		return;
	if (runIndex < 0 || runIndex >= [attachedLogs count])
		runIndex = [attachedLogs count] - 1;
	currentConnection = [attachedLogs objectAtIndex:runIndex];
}

- (NSArray *)attachedLogsPopupNames
{
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:[attachedLogs count]];
	NSUInteger count = [attachedLogs count];
	if (count == 1)
	{
		int reconnectionCount = ((LoggerConnection *)[attachedLogs lastObject]).reconnectionCount + 1;
		[array addObject:[NSString stringWithFormat:NSLocalizedString(@"Run %d", @""), reconnectionCount]];
	}
	else for (NSInteger i=0; i < count; i++)
		[array addObject:[NSString stringWithFormat:NSLocalizedString(@"Run %d of %d", @""), i+1, count]];
	return array;
}

- (void)addConnection:(LoggerConnection *)newConnection
{
	newConnection.delegate = self;
	[attachedLogs addObject:newConnection];

	dispatch_async(dispatch_get_main_queue(), ^{
		// add the new connection to our list, potentially clearing previous ones
		// if prefs say we shouldn't keep previous logs around
		currentConnection = nil;
		[self willChangeValueForKey:@"attachedLogsPopupNames"];
		if (![[NSUserDefaults standardUserDefaults] boolForKey:kPrefKeepMultipleRuns])
		{
			while ([attachedLogs count] > 1)
				[attachedLogs removeObjectAtIndex:0];
		}
		[self didChangeValueForKey:@"attachedLogsPopupNames"];
		currentConnection = newConnection;

		// switch the document's associated main window to show this new connection
		self.indexOfCurrentVisibleLog = [NSNumber numberWithInteger:[attachedLogs indexOfObjectIdenticalTo:newConnection]];
	});
}

- (void)clearLogs:(BOOL)includingPreviousRuns
{
	LoggerConnection *connection = [attachedLogs lastObject];

	if (includingPreviousRuns)
	{
		// Remove all previous run logs
		[self willChangeValueForKey:@"attachedLogsPopupNames"];
		while ([attachedLogs count] > 1)
			[attachedLogs removeObjectAtIndex:0];
		connection.reconnectionCount = 0;
		[self didChangeValueForKey:@"attachedLogsPopupNames"];
	}

	// Remove all entries from current run log
	dispatch_async(connection.messageProcessingQueue, ^{
		[connection clearMessages];
		dispatch_async(dispatch_get_main_queue(), ^{
			// this forces a full refresh of the view in a clean way
			self.indexOfCurrentVisibleLog = self.indexOfCurrentVisibleLog;
		});
	});
}

- (NSNumber *)indexOfCurrentVisibleLog
{
	NSInteger idx = [attachedLogs indexOfObjectIdenticalTo:currentConnection];
	assert(idx != NSNotFound || currentConnection == nil);
	if (idx == NSNotFound)
		idx = [attachedLogs count] - 1;
	return [NSNumber numberWithInteger:idx];
}

- (void)setIndexOfCurrentVisibleLog:(NSNumber *)anIndex
{
	assert([NSThread isMainThread]);

	// First, close all non-main window attached windows
	NSMutableArray *windowsToClose = [NSMutableArray array];
	LoggerWindowController *mainWindow = nil;
	for (NSWindowController *wc in [self windowControllers])
	{
		if (![wc isKindOfClass:[LoggerWindowController class]])
			[windowsToClose addObject:wc];
		else
			mainWindow = (LoggerWindowController *)wc;
	}
	for (NSWindowController *wc in windowsToClose)
		[wc close];
	
	// Changed the attached connection
	[self willChangeValueForKey:@"indexOfCurrentVisibleLog"];
	[self selectRun:[anIndex integerValue]];
	mainWindow.attachedConnection = currentConnection;
	[self didChangeValueForKey:@"indexOfCurrentVisibleLog"];
	
	// Bring window to front
	[mainWindow showWindow:self];
    
    //MM ADDITION POINT:
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPrefUseConnectionManager]) {
        [mainWindow.window orderOut:nil];
    }
}

- (void)dealloc
{
	for (LoggerConnection *connection in attachedLogs)
	{
		// close the connection (if not already done) and make sure it is removed from transport
		for (LoggerTransport *t in ((LoggerAppDelegate *)[NSApp	delegate]).transports)
			[t removeConnection:connection];
	}
	[attachedLogs release];
	[super dealloc];
}


- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
        
	if ([typeName isEqualToString:@"NSLogger Data"])
	{
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:attachedLogs];
		if (data != nil)
			return [data writeToURL:absoluteURL atomically:NO];
	}
	else if ([typeName isEqualToString:@"public.plain-text"])
	{
		// Export messages as text. Only the current visible connection is exported at text
		// Make a copy of the array state now so we're not bothered with the array
		// changing while we're processing it
		NSInteger connectionIndex = [[self indexOfCurrentVisibleLog] integerValue];
		assert(connectionIndex != NSNotFound);
		LoggerConnection *connection = [attachedLogs objectAtIndex:connectionIndex];
		__block NSArray *allMessages = nil;
		dispatch_sync(connection.messageProcessingQueue , ^{
			allMessages = [[NSArray alloc] initWithArray:connection.messages];
		});

		BOOL (^flushData)(NSOutputStream*, NSMutableData*) = ^(NSOutputStream *stream, NSMutableData *data) 
		{
			NSUInteger length = [data length];
			const uint8_t *bytes = [data bytes];
			BOOL result = NO;
			if (length && bytes != NULL)
			{
				NSInteger written = [stream write:bytes maxLength:length];
				result = (written == length);
			}
			[data setLength:0];
			return result;
		};

		BOOL result = NO;
		NSOutputStream *stream = [[NSOutputStream alloc] initWithURL:absoluteURL append:NO];
		if (stream != nil)
		{
			const NSUInteger bufferCapacity = 1024 * 1024;
			NSMutableData *data = [[NSMutableData alloc] initWithCapacity:bufferCapacity];
			uint8_t bom[3] = {0xEF, 0xBB, 0xBF};
			[data appendBytes:bom length:3];
			NSAutoreleasePool *pool = nil;
			result = YES;
			[stream open];
			for (LoggerMessage *message in allMessages)
			{
				[data appendData:[[message textRepresentation] dataUsingEncoding:NSUTF8StringEncoding]];
				if ([data length] >= bufferCapacity)
				{
					// periodic flush to reduce memory use while exporting
					result = flushData(stream, data);
					[pool release];
					pool = [[NSAutoreleasePool alloc] init];
					if (!result)
						break;
				}
			}
			if (result)
				result = flushData(stream, data);
			[stream close];
			[pool release];
			[data release];
			[stream release];
		}
		[allMessages release];
		return result;
	}
    
    
    
	return NO;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	assert([attachedLogs count] == 0);
	NSUInteger previousLogs = [attachedLogs count];

	if ([typeName isEqualToString:@"NSLogger Data"])
	{
		id logs = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		if ([logs isKindOfClass:[LoggerConnection class]])
			[attachedLogs addObject:logs];
		else
			[attachedLogs addObjectsFromArray:logs];
	}
	else if ([typeName isEqualToString:@"NSLogger Raw Data"])
	{
		LoggerConnection *connection = [[[LoggerConnection alloc] init] autorelease];
		[attachedLogs addObject:connection];

		NSMutableArray *msgs = [[NSMutableArray alloc] init];
		long dataLength = [data length];
		const uint8_t *p = [data bytes];
		while (dataLength)
		{
			// check whether we have a full message
			uint32_t length;
			memcpy(&length, p, 4);
			length = ntohl(length);
			if (dataLength < (length + 4))
				break;		// incomplete last message
			
			// get one message
			CFDataRef subset = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
														   (unsigned char *)p + 4,
														   length,
														   kCFAllocatorNull);
			if (subset != NULL)
			{
				LoggerMessage *message = [[LoggerNativeMessage alloc] initWithData:(NSData *)subset connection:connection];
				if (message.type == LOGMSG_TYPE_CLIENTINFO)
					[connection clientInfoReceived:message];
				else
					[msgs addObject:message];
				[message release];
				CFRelease(subset);
			}
			dataLength -= length + 4;
			p += length + 4;
		}
		if ([msgs count])
			[connection messagesReceived:msgs];
		[msgs release];
	}
	currentConnection = [attachedLogs lastObject];
	return ([attachedLogs count] != previousLogs);
}

- (void)makeWindowControllers
{
	LoggerWindowController *controller = [[LoggerWindowController alloc] initWithWindowNibName:@"LoggerWindow"];
	[self addWindowController:controller];
	[controller release];

	// force assignment of the current connection to the main window
	self.indexOfCurrentVisibleLog = [NSNumber numberWithInteger:[attachedLogs indexOfObjectIdenticalTo:currentConnection]];
}

/////////////////////////////MM ADDITION POINT:

- (void)hideMainWindow {
    
    if ([self.windowControllers count] > 0) {
        
    LoggerWindowController *controller = [self.windowControllers objectAtIndex:0];
    [controller.window orderOut:nil];
        
    }
}

- (void)showMainWindow {
    
    if ([self.windowControllers count] > 0) {

        LoggerWindowController *controller = [self.windowControllers objectAtIndex:0];
        [controller showWindow:nil];
        [controller.window makeKeyAndOrderFront:nil]; // to actually show it
    }
    
}

- (void)saveThisLog {
    //Calculate the path:
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPrefUseConnectionManager]) {
        
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *mainDirectory = [[NSUserDefaults standardUserDefaults] objectForKey:@"preferredLogPath"];
	NSString *subdirectory = [NSString stringWithFormat:@"%@/%@",self.currentConnection.clientName,self.currentConnection.clientUDID];
    
    NSDate *today = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"dd-MM-yyyy"];
    NSString *dateString = [dateFormatter stringFromDate:today];
    
    NSString *directory = [NSString stringWithFormat:@"%@/%@/%@/",[mainDirectory stringByExpandingTildeInPath],subdirectory,dateString];
    [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    
    [dateFormatter setDateFormat:@"HH-mm-ss"];
    NSString *timeString = [dateFormatter stringFromDate:today];
    
    NSString *thisFile = [NSString stringWithFormat:@"%@.nsloggerdata",timeString];
    
	NSString *filePath = [directory stringByAppendingString:thisFile];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    //Performing actual save:
    [self saveToURL:fileURL ofType:@"NSLogger Data" forSaveOperation:NSSaveToOperation delegate:self didSaveSelector:@selector(saveDidFinish) contextInfo:nil];
    
    }
}

-(void)saveDidFinish {

    //Flush the log:
    [self clearLogs:YES];
    [self hideMainWindow];

}

-(void)makeDisconnected {
    
    if (idleTimer != nil && [idleTimer isValid]) {
        [idleTimer invalidate];
        idleTimer = nil;
    }
    
    self.active = NO;
    self.disconnected = YES;
    self.idle = NO;
}

-(void)makeIdle {
    idleTimer = nil;
    
    self.active = NO;
    self.disconnected = NO;
    self.idle = YES;
    
    [(LoggerAppDelegate *)[NSApp delegate] reloadSubtable];
}

-(void)makeActive {
    self.active = YES;
    self.disconnected = NO;
    self.idle = NO;

    [(LoggerAppDelegate *)[NSApp delegate] reloadSubtable];
}


////////////////////////////



- (BOOL)prepareSavePanel:(NSSavePanel *)sp
{
    // assign defaults for the save panel
    [sp setTitle:NSLocalizedString(@"Save Logs", @"")];
    [sp setExtensionHidden:NO];
        
    return YES;
}

- (NSArray *)writableTypesForSaveOperation:(NSSaveOperationType)saveOperation
{
	NSArray *array = [super writableTypesForSaveOperation:saveOperation];
	if (saveOperation == NSSaveToOperation)
		array = [array arrayByAddingObject:@"public.plain-text"];
	return array;
}



- (LoggerWindowController *)mainWindowController
{
	for (LoggerWindowController *controller in [self windowControllers])
	{
		if ([controller isKindOfClass:[LoggerWindowController class]])
			return controller;
	}
    
	assert(false);
	return nil;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark LoggerConnectionDelegate
// -----------------------------------------------------------------------------
- (void)connection:(LoggerConnection *)theConnection
didReceiveMessages:(NSArray *)theMessages
			 range:(NSRange)rangeInMessagesList
{
	LoggerWindowController *wc = [self mainWindowController];
	if (wc.attachedConnection == theConnection)
		[wc connection:theConnection didReceiveMessages:theMessages range:rangeInMessagesList];
	if (theConnection.connected)
	{
        if (self.idle || self.disconnected) {
            [self makeActive];
        }
        
        self.active = YES;
        self.idle = NO;
        self.disconnected = NO;
        
        
        messageCounter += 1;
        if (messageCounter > SAVING_MESSAGES_INTERVAL) {
            //Reset Counter;
            messageCounter = 0;
            
            //Perform Log save:
            [self saveThisLog];
        }
        
		// fixed a crash where calling updateChangeCount: which does not appear to be
		// safe when called from a secondary thread
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateChangeCount:NSChangeDone];
            
            
            //MM ADDITION POINT
            if (idleTimer != nil && [idleTimer isValid]) {
                [idleTimer invalidate];
                idleTimer = nil;
            }
            
            idleTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)IDLE_DEFINITION_TIME
                                                         target:self
                                                       selector:@selector(makeIdle)
                                                       userInfo:nil
                                                        repeats:NO];
		});
	}
}

- (void)remoteDisconnected:(LoggerConnection *)theConnection
{
    
	LoggerWindowController *wc = [self mainWindowController];
	if (wc.attachedConnection == theConnection)
		[wc remoteDisconnected:theConnection];
    
    //MM ADDITION POINT
    //Perform Log save:
    [self saveThisLog];
    [self makeDisconnected];
    
}

@end
