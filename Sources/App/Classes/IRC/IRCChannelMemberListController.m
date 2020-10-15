/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *	* Redistributions of source code must retain the above copyright
 *	  notice, this list of conditions and the following disclaimer.
 *	* Redistributions in binary form must reproduce the above copyright
 *	  notice, this list of conditions and the following disclaimer in the
 *	  documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual and/or Codeux Software, nor the names of
 *    its contributors may be used to endorse or promote products derived
 * 	  from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

#import "IRCChannelPrivate.h"
#import "IRCChannelMemberList.h"
#import "IRCChannelMemberListControllerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCChannelMemberList ()
- (void)assignController:(nullable IRCChannelMemberListController *)controller;
@end

@interface IRCChannelMemberListController ()
@property (nonatomic, weak) IRCChannelMemberList *memberList;
@property (nonatomic, weak) IBOutlet NSTableView *tableView;
@end

@implementation IRCChannelMemberListController

- (void)assignToChannel:(nullable IRCChannel *)channel
{
	/* Modify table sources */
	NSTableView *tableView = self.tableView;

	tableView.dataSource = (id)channel;
	tableView.delegate = (id)channel;

	/* Are we assigned? */
	IRCChannelMemberList *oldList = self.memberList;

	if ( oldList) {
		[oldList assignController:nil];

		self.memberList = nil;

		/* If we were already assigned to a list, but will now be
		 assigned to nothing, then clear contents and do nothing more. */
		if (channel == nil) {
			self.content = @[];

			return;
		}
	}

	/* Assign to channel */
	IRCChannelMemberList *newList = channel.memberInfo;

	[newList assignController:self];

	self.memberList = newList;
}

- (void)replaceContents:(NSArray<IRCChannelUser *> *)contents
{
	NSParameterAssert(contents != nil);

	self.content = [contents mutableCopy];
}

@end

NS_ASSUME_NONNULL_END