/* *********************************************************************
                  _____         _               _
                 |_   _|____  _| |_ _   _  __ _| |
                   | |/ _ \ \/ / __| | | |/ _` | |
                   | |  __/>  <| |_| |_| | (_| | |
                   |_|\___/_/\_\\__|\__,_|\__,_|_|

 Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 Copyright (c) 2010 - 2015 Codeux Software, LLC & respective contributors.
        Please see Acknowledgements.pdf for additional information.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Textual and/or "Codeux Software, LLC", nor the 
      names of its contributors may be used to endorse or promote products 
      derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.

 *********************************************************************** */

NS_ASSUME_NONNULL_BEGIN

#define _autoConnectDelay				1

#define _reconnectAfterWakeupDelay		8

#define _savePeriodicallyThreshold		300

NSString * const IRCWorldClientListDefaultsKey = @"World Controller Client Configurations";

NSString * const IRCWorldClientListWasModifiedNotification = @"IRCWorldClientListWasModifiedNotification";

NSString * const IRCWorldDateHasChangedNotification = @"IRCWorldDateHasChangedNotification";

@interface IRCWorld ()
@property (nonatomic, strong) NSMutableArray<IRCClient *> *clients;
@property (nonatomic, assign) BOOL preferencesDidChangeTimerIsActive;
@property (nonatomic, assign) CFAbsoluteTime savePeriodicallyLastSave;
@end

@implementation IRCWorld

#pragma mark -
#pragma mark Initialization

- (instancetype)init
{
	if ((self = [super init])) {
		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	self.clients = [NSMutableArray new];

	self.preferencesDidChangeTimerIsActive = NO;

	self.savePeriodicallyLastSave = CFAbsoluteTimeGetCurrent();
}

- (void)dealloc
{
	[self cancelPerformRequests];
}

#pragma mark -
#pragma mark Configuration

- (void)setupConfiguration
{
	self.isImportingConfiguration = YES;

	[mainWindowServerList() beginUpdates];

	NSArray *clientList = [TPCPreferences clientList];

	for (NSDictionary *client in clientList) {
		IRCClientConfig *e = [[IRCClientConfig alloc] initWithDictionary:client];

		[self createClientWithConfig:e reload:YES];
	}

	[mainWindowServerList() endUpdates];

	self.isImportingConfiguration = NO;

	[self setupOtherServices];
}

- (void)setupOtherServices
{
	[self setupMidnightTimer];

	[RZNotificationCenter() addObserver:self selector:@selector(dateChanged:) name:NSSystemClockDidChangeNotification object:nil];

	[RZNotificationCenter() addObserver:self selector:@selector(userDefaultsDidChange:) name:TPCPreferencesUserDefaultsDidChangeNotification object:nil];
}

- (NSArray *)clientConfigurations
{
	NSMutableArray *ary = [NSMutableArray array];

	for (IRCClient *u in self.clientList) {
		[ary addObject:[u configurationDictionary]];
	}

	return [ary copy];
}

- (void)save
{
	NSArray *clientList = [self clientConfigurations];

	[TPCPreferences setClientList:clientList];
}

- (void)savePeriodically
{
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

	if ((self.savePeriodicallyLastSave + _savePeriodicallyThreshold) < now) {
		 self.savePeriodicallyLastSave = now;

		[self save];
	}
}

- (void)prepareForApplicationTermination
{
	[RZNotificationCenter() removeObserver:self];

	for (IRCClient *u in self.clientList) {
		[u prepareForApplicationTermination];
	}
}

- (void)userDefaultsDidChange:(NSNotification *)notification
{
	if (themeSettings().js_postPreferencesDidChangesNotifications == NO) {
		return; // Cancel operation...
	}

	if (self.preferencesDidChangeTimerIsActive == NO) {
		self.preferencesDidChangeTimerIsActive = YES;

		[self performSelector:@selector(informaAllViewsUserDefaultsDidChange) withObject:nil afterDelay:1.0];
	}
}

- (void)informaAllViewsUserDefaultsDidChange
{
	self.preferencesDidChangeTimerIsActive = NO;

	[self evaluateFunctionOnAllViews:@"preferencesDidChange" arguments:nil onQueue:YES];
}

#pragma mark -
#pragma mark Properties

- (NSArray<IRCClient *> *)clientList
{
	@synchronized(self.clients) {
		return [NSArray arrayWithArray:self.clients];
	}
}

- (void)setClientList:(NSArray<IRCClient *> *)clientList
{
	@synchronized(self.clients) {
		[self.clients removeAllObjects];

		[self.clients addObjectsFromArray:clientList];

		[self postClientListWasModifiedNotification];
	}
}

- (NSUInteger)clientCount
{
	@synchronized(self.clients) {
		return self.clients.count;
	}
}

#pragma mark -
#pragma mark Utilities

- (void)postClientListWasModifiedNotification
{
	[RZNotificationCenter() postNotificationName:IRCWorldClientListWasModifiedNotification object:self];
}

- (void)autoConnectAfterWakeup:(BOOL)afterWakeUp
{
	if (masterController().ghostModeIsOn && afterWakeUp == NO) {
		return;
	}

	NSUInteger delay = 0;

	if (afterWakeUp) {
		delay += _reconnectAfterWakeupDelay;
	}

#define _isAutoConnecting		(afterWakeUp == NO && u.config.autoConnect)
#define _isWakingFromSleep		(afterWakeUp	   && u.config.autoSleepModeDisconnect && u.disconnectType == IRCClientDisconnectComputerSleepMode)

	for (IRCClient *u in self.clientList) {
		if (_isWakingFromSleep == NO && _isAutoConnecting == NO) {
			continue;
		}

		[u autoConnectWithDelay:delay afterWakeUp:afterWakeUp];

		delay += _autoConnectDelay;
	}

#undef _isWakingFromSleep
#undef _isAutoConnecting
}

- (void)prepareForSleep
{
	for (IRCClient *u in self.clientList) {
		if (u.config.autoSleepModeDisconnect == NO) {
			continue;
		}

		if (u.isLoggedIn == NO) {
			continue;
		}

#warning TODO: -quit should auto fill -sleepModeLeavingComment when \
	the value of disconnectType is IRCClientDisconnectComputerSleepMode
		u.disconnectType = IRCClientDisconnectComputerSleepMode;

		[u quit];
	}
}

- (void)prepareForScreenSleep
{
	if ([TPCPreferences setAwayOnScreenSleep] == NO) {
		return;
	}

	for (IRCClient *u in self.clientList) {
		[u toggleAwayStatus:YES];
	}
}

- (void)wakeFomScreenSleep
{
	if ([TPCPreferences setAwayOnScreenSleep] == NO) {
		return;
	}

	for (IRCClient *u in self.clientList) {
		[u toggleAwayStatus:NO];
	}
}

- (void)noteReachabilityChanged:(BOOL)reachable
{
	for (IRCClient *u in self.clientList) {
		[u noteReachabilityChanged:reachable];
	}
}

- (void)preferencesChanged
{
	[menuController() preferencesChanged];

	for (IRCClient *u in self.clientList) {
		[u preferencesChanged];
	}

	[TVCImageURLoader invalidateInternalCache];
}

- (void)setupMidnightTimer
{
	[self setupMidnightTimerWithNotification:NO];
}

- (void)setupMidnightTimerWithNotification:(BOOL)fireNotification
{
	/* Ask for the day, month, and year from the current calender. */
	/* We are not asking for time which means that it will default to zero. */
	NSDateComponents *currentDayComponents = [RZCurrentCalender() components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:[NSDate date]];

	NSDate *lastMidnight = [RZCurrentCalender() dateFromComponents:currentDayComponents];

	/* Create date components one day in the future. */
	/* All other values default to zero. */
	NSDateComponents *futureDayComponents = [NSDateComponents new];

	futureDayComponents.day = 1;

	/* With the current date and future components, calculate
	 the date on which our midnight timer will land. */
	NSDate *nextMidnight = [RZCurrentCalender() dateByAddingComponents:futureDayComponents toDate:lastMidnight options:0];

	/* Create timer for midnight in future. */
	/* We set the tolerance for the timer to absolute zero so that
	 we are confident that OS X will not reschedule it. */
	NSTimer *midnightTimer = [[NSTimer alloc]
				initWithFireDate:nextMidnight
						interval:0.0
						  target:self
						selector:@selector(dateChanged:)
						userInfo:nil
						 repeats:NO];

	if ([XRSystemInformation isUsingOSXMavericksOrLater]) {
		midnightTimer.tolerance = 0.0;
	}

	/* Schedule the timer on the run loop which will retain reference. */
	[RZCurrentRunLoop() addTimer:midnightTimer forMode:NSDefaultRunLoopMode];

	/* Post notification if needed. */
	if (fireNotification) {
		[RZNotificationCenter() postNotificationName:IRCWorldDateHasChangedNotification object:nil userInfo:nil];

		[self evaluateFunctionOnAllViews:@"Textual.dateChanged"
							   arguments:@[@(currentDayComponents.year),
										   @(currentDayComponents.month),
										   @(currentDayComponents.day)]
								 onQueue:NO];
	}
}

- (void)dateChanged:(id)sender
{
	/* We call the notifications in the timer so we do not have to
	 ask for the current day components two times. */

	[self setupMidnightTimerWithNotification:YES];
}

#pragma mark -
#pragma mark Tree Items

- (nullable IRCTreeItem *)findItemWithId:(NSString *)itemId
{
	if (itemId == nil) {
		return nil;
	}

	for (IRCClient *u in self.clientList) {
		if ([itemId isEqualToString:u.uniqueIdentifier]) {
			return u;
		}

		for (IRCChannel *c in u.channelList) {
			if ([itemId isEqualToString:c.uniqueIdentifier]) {
				return c;
			}
		}
	}

	return nil;
}

- (nullable IRCClient *)findClientWithId:(NSString *)clientId
{
	return (IRCClient *)[self findItemWithId:clientId];
}

- (nullable IRCChannel *)findChannelWithId:(NSString *)channelId onClientWithId:(NSString *)clientId
{
	return (IRCChannel *)[self findItemWithId:channelId];
}

- (nullable IRCTreeItem *)findItemWithPasteboardString:(NSString *)string
{
	return [self findItemWithId:string];
}

- (NSString *)pasteboardStringForItem:(IRCTreeItem *)item
{
	NSParameterAssert(item != nil);

	return item.uniqueIdentifier;
}

#pragma mark -
#pragma mark JavaScript

- (void)evaluateFunctionOnAllViews:(NSString *)function arguments:(nullable NSArray *)arguments
{
	[self evaluateFunctionOnAllViews:function arguments:arguments onQueue:YES];
}

- (void)evaluateFunctionOnAllViews:(NSString *)function arguments:(nullable NSArray *)arguments onQueue:(BOOL)onQueue
{
	NSParameterAssert(function != nil);

	if (masterController().applicationIsTerminating) {
		return;
	}

	for (IRCClient *u in self.clientList) {
		[u.viewController evaluateFunction:function withArguments:arguments onQueue:onQueue];

		for (IRCChannel *c in u.channelList) {
			[c.viewController evaluateFunction:function withArguments:arguments onQueue:onQueue];
		}
	}
}

#pragma mark -
#pragma mark Factory

- (IRCClient *)createClientWithConfig:(IRCClientConfig *)config
{
	return [self createClientWithConfig:config reload:YES];
}

- (IRCClient *)createClientWithConfig:(IRCClientConfig *)config reload:(BOOL)reload
{
	NSParameterAssert(config != nil);

	IRCClient *client = [[IRCClient alloc] initWithConfig:config];

	client.printingQueue = [TVCLogControllerOperationQueue new];

	client.viewController = [self createViewControllerWithClient:client channel:nil];

	for (IRCChannelConfig *channel in client.config.channelList) {
		[self createChannelWithConfig:channel onClient:client adjust:NO reload:NO];
	}

	@synchronized(self.clients) {
		[self.clients addObject:client];

		if (reload) {
			NSInteger index = [self.clients indexOfObject:client];

			[mainWindowServerList() addItemToList:index inParent:nil];
		}

		if (self.clients.count == 1) {
			[mainWindow() select:client];
		}
	}

	(void)[mainWindow() reloadLoadingScreen];

	[menuController() populateNavgiationChannelList];

	[self postClientListWasModifiedNotification];

	return client;
}

- (IRCChannel *)createChannelWithConfig:(IRCChannelConfig *)config onClient:(IRCClient *)client
{
	return [self createChannelWithConfig:config onClient:client adjust:YES reload:YES];
}

- (IRCChannel *)createChannelWithConfig:(IRCChannelConfig *)config onClient:(IRCClient *)client adjust:(BOOL)adjust reload:(BOOL)reload
{
	NSParameterAssert(config != nil);
	NSParameterAssert(client != nil);

	IRCChannel *channel = [[IRCChannel alloc] initWithConfig:config];

	channel.associatedClient = client;

	channel.viewController = [self createViewControllerWithClient:client channel:channel];

	[client addChannel:channel];

	if (reload) {
		NSInteger index = [client.channelList indexOfObject:channel];

		[mainWindowServerList() addItemToList:index inParent:client];
	}

	if (adjust) {
		[mainWindow() adjustSelection];

		[menuController() populateNavgiationChannelList];
	}

	return channel;
}

- (IRCChannel *)createPrivateMessage:(NSString *)nickname onClient:(IRCClient *)client
{
	NSParameterAssert(nickname != nil);
	NSParameterAssert(client != nil);

	IRCChannelConfigMutable *config = [IRCChannelConfigMutable new];

	config.channelName = nickname;

	config.type = IRCChannelPrivateMessageType;

	IRCChannel *channel = [self createChannelWithConfig:config onClient:client adjust:YES reload:YES];

	if (client.isLoggedIn) {
		[channel activate];
	}

	return channel;
}

- (TVCLogController *)createViewControllerWithClient:(IRCClient *)client channel:(nullable IRCChannel *)channel
{
	NSParameterAssert(client != nil);

	TVCLogController *viewController = nil;

	if (channel == nil) {
		viewController = [[TVCLogController alloc] initWithClient:client inWindow:mainWindow()];
	} else {
		viewController = [[TVCLogController alloc] initWithChannel:channel inWindow:mainWindow()];
	}

	return viewController;
}

- (void)selectOtherBeforeDestroy:(IRCTreeItem *)target
{
	NSParameterAssert(target != nil);

	if (target.isClient) {
		[mainWindow() deselectGroup:target];
	} else {
		[mainWindow() deselect:target];
	}
}

- (void)destroyClient:(IRCClient *)client
{
	[self destroyClient:client skipCloud:NO];
}

- (void)destroyClient:(IRCClient *)client skipCloud:(BOOL)skipCloud
{
	NSParameterAssert(client != nil);

	/* It is not safe to destroy the client while connected. */
	if (client.isConnecting || client.isConnected) {
		__weak IRCWorld *weakSelf = self;

		__weak IRCClient *weakClient = client;

		client.disconnectCallback = ^{
			[weakSelf destroyClient:weakClient skipCloud:skipCloud];
		};

		[client quit];

		return;
	}

	[self selectOtherBeforeDestroy:client];

	[client prepareForPermanentDestruction];

	client.printingQueue = nil;

#if TEXTUAL_BUILT_WITH_ICLOUD_SUPPORT == 1
	if (skipCloud == NO) {
		[self cloud_destroyClient:client];
	}
#endif

	[mainWindowServerList() removeItemFromList:client];

	@synchronized(self.clients) {
		[self.clients removeObjectIdenticalTo:client];
	}

	[self postClientListWasModifiedNotification];

	(void)[mainWindow() reloadLoadingScreen];

	[menuController() populateNavgiationChannelList];
}

- (void)destroyChannel:(IRCChannel *)channel
{
	[self destroyChannel:channel reload:YES part:YES];
}

- (void)destroyChannel:(IRCChannel *)channel reload:(BOOL)reload
{
	[self destroyChannel:channel reload:reload part:YES];
}

- (void)destroyChannel:(IRCChannel *)channel reload:(BOOL)reload part:(BOOL)partChannel
{
	NSParameterAssert(channel != nil);

	IRCClient *client = channel.associatedClient;

	if (partChannel) {
		[client partChannel:channel];
	}

	if (reload) {
		[self selectOtherBeforeDestroy:channel];
	}

	[client willDestroyChannel:channel];

	[channel prepareForPermanentDestruction];

	if (client.lastSelectedChannel == channel) {
		client.lastSelectedChannel = nil;
	}

	if (reload) {
		[mainWindowServerList() removeItemFromList:channel];

		[client removeChannel:channel];

		[mainWindow() adjustSelection];
		
		[menuController() populateNavgiationChannelList];
	}
}

@end

NS_ASSUME_NONNULL_END
