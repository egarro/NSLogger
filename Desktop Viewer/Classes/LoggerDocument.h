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
#import "LoggerConnection.h"
#import "MMLogSaverController.h"

@class LoggerWindowController;

typedef enum {
    active,
	idle,
	killed,         //Disconnected
	unknown,
    maxDocumentStatus
} DocumentStatus;


@interface LoggerDocument : NSDocument <LoggerConnectionDelegate, MMLogSaverDelegate>
{
	NSMutableArray *attachedLogs;
	LoggerConnection *currentConnection;			// the connection currently visible in the main window

    //MM ADDITION POINT
    
    NSUInteger tag;
    NSUInteger messageCounter;
    NSUInteger idleDefinitionTime;
    NSUInteger maximumMessagesPerLog;
    MMLogSaverController *saverController;
    
    DocumentStatus status;
    
    NSTimer *idleTimer;
    
}

@property (nonatomic, readwrite) NSUInteger tag;
@property (nonatomic, readonly) NSMutableArray *attachedLogs;
@property (nonatomic, retain) NSNumber *indexOfCurrentVisibleLog;
@property (nonatomic, assign) LoggerConnection *currentConnection;
@property (nonatomic, assign) DocumentStatus status;
@property (nonatomic, assign) MMLogSaverController *saverController;

+ (NSString *)stringForDocumentStatus:(DocumentStatus)aStatus;

- (id)initWithConnection:(LoggerConnection *)aConnection;
- (LoggerWindowController *)mainWindowController;
- (NSArray *)attachedLogsPopupNames;
- (void)addConnection:(LoggerConnection *)newConnection;


//MM ADDITION POINT:
- (void)createSaverController;
- (void)attachConnectionToWindowController;
- (void)destroyMainWindow;
- (void)showMainWindow;
- (void)saveThisLog;
- (void)updateClientInfo;

@end
