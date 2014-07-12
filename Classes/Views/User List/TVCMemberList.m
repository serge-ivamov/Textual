/* ********************************************************************* 
       _____        _               _    ___ ____   ____
      |_   _|___  _| |_ _   _  __ _| |  |_ _|  _ \ / ___|
       | |/ _ \ \/ / __| | | |/ _` | |   | || |_) | |
       | |  __/>  <| |_| |_| | (_| | |   | ||  _ <| |___
       |_|\___/_/\_\\__|\__,_|\__,_|_|  |___|_| \_\\____|

 Copyright (c) 2010 — 2014 Codeux Software & respective contributors.
     Please see Acknowledgements.pdf for additional information.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Textual IRC Client & Codeux Software nor the
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

#import "TextualApplication.h"

@interface TVCMemberList ()
@property (nonatomic, assign) BOOL beginUpdatesCallRunning;
@property (nonatomic, strong) id userPopoverTrackingArea;
@property (nonatomic, assign) BOOL userPopoverMouseIsInView;
@property (nonatomic, assign) BOOL userPopoverTimerIsActive;
@property (nonatomic, assign) NSPoint userPopoverLastKnonwnLocalPoint;
@property (nonatomic, assign) NSInteger lastRowShownUserInfoPopover;
@end

@implementation TVCMemberList

- (void)dealloc
{
	/* Remove notifications for scroll view. */
	[RZNotificationCenter() removeObserver:self
									  name:NSViewBoundsDidChangeNotification
									object:[self scrollViewContentView]];
}

#pragma mark -
#pragma mark Update Grouping

- (BOOL)updatesArePaging
{
	return self.beginUpdatesCallRunning;
}

- (void)beginGroupedUpdates
{
	NSAssertReturn(self.beginUpdatesCallRunning == NO);

	self.beginUpdatesCallRunning = YES;
	
	[self beginUpdates];
}

- (void)endGroupedUpdates
{
	NSAssertReturn(self.beginUpdatesCallRunning);
	
	self.beginUpdatesCallRunning = NO;
	
	[self endUpdates];
}

#pragma mark -
#pragma mark Additions/Removal

- (void)addItemToList:(NSInteger)index
{
	NSAssertReturn(index >= 0);

	[self insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:index]
					  inParent:nil
				 withAnimation:NSTableViewAnimationEffectNone];
}

- (void)removeItemFromList:(id)oldObject
{
	/* Get the row. */
	NSInteger rowIndex = [self rowForItem:oldObject];

	NSAssertReturn(rowIndex >= 0);

	/* Remove object. */
	[self removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:rowIndex]
					  inParent:nil
				 withAnimation:NSTableViewAnimationEffectNone];
}

#pragma mark -
#pragma mark Events

- (NSMenu *)menuForEvent:(NSEvent *)e
{
	NSIndexSet *selectedRows = [self selectedRowIndexes];

	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];

	NSInteger i = [self rowAtPoint:p];

	if (i >= 0 && [selectedRows containsIndex:i] == NO) {
		[self selectItemAtIndex:i];
	}
	
	return [menuController() userControlMenu];
}

- (void)keyDown:(NSEvent *)e
{
	if (self.keyDelegate) {
		switch ([e keyCode]) {
			case 123 ... 126:
			case 116:
			case 121:
			{
				break;
			}
			default:
			{
				if ([self.keyDelegate respondsToSelector:@selector(memberListViewKeyDown:)]) {
					[self.keyDelegate memberListViewKeyDown:e];
				}
				
				break;
			}
		}
	}
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
	TVCMainWindowNegateActionWithAttachedSheet();

	[super rightMouseDown:theEvent];
}

#pragma mark -
#pragma mark Mouse Tracking

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		self.userPopoverTrackingArea = [[NSTrackingArea alloc] initWithRect:frame
																	options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow)
																	  owner:self
																   userInfo:nil];

		[self addTrackingArea:self.userPopoverTrackingArea];

		return self;
	}

	return nil;
}

- (void)updateTrackingAreas
{
    [self removeTrackingArea:self.userPopoverTrackingArea];
	
	self.userPopoverTrackingArea = [[NSTrackingArea alloc] initWithRect:[self frame]
																options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow)
																  owner:self
															   userInfo:nil];

	[self addTrackingArea:self.userPopoverTrackingArea];
}

- (void)destroyUserInfoPopoverOnWindowKeyChange
{
	[self destroyUserInfoPopover]; // Destroy anything shown.
}

- (void)destroyUserInfoPopover
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(popDelayedUserInfoExpansionFrame) object:nil];

	self.lastRowShownUserInfoPopover = -1;

	self.userPopoverMouseIsInView = NO;
	self.userPopoverTimerIsActive = NO;

	self.userPopoverLastKnonwnLocalPoint = NSZeroPoint;

	if ([self.memberListUserInfoPopover isShown]) {
		[self.memberListUserInfoPopover close];
	}
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	self.userPopoverMouseIsInView = YES;

	if (self.userPopoverTimerIsActive == NO) {
		self.userPopoverTimerIsActive = YES;

		[self performSelector:@selector(popDelayedUserInfoExpansionFrame) withObject:nil afterDelay:1.0];
	}
}

- (void)mouseExited:(NSEvent *)theEvent
{
	[self destroyUserInfoPopover];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	NSPoint localPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];

	[self popUserInfoExpansionFrameAtPoint:localPoint ignoreTimerCheck:NO];
}

- (void)popUserInfoExpansionFrameAtPoint:(NSPoint)localPoint ignoreTimerCheck:(BOOL)ignoreTimer
{
	self.userPopoverLastKnonwnLocalPoint = localPoint;

	if (ignoreTimer == NO && self.userPopoverTimerIsActive) {
		return; // Only allow the timer to pop it.
	}

	NSInteger row = [self rowAtPoint:localPoint];

	if (row > -1) {
		if (NSDissimilarObjects(self.lastRowShownUserInfoPopover, row)) {
			self.lastRowShownUserInfoPopover = row;

			id rowView = [self viewAtColumn:0 row:row makeIfNecessary:NO];

			[rowView drawWithExpansionFrame];
		}
	}
}

- (void)popDelayedUserInfoExpansionFrame
{
	/* Basically we delay the expansion frame (also known as the popover)
	 by one second from the time the user enters the frame so that if they
	 are just moving the mouse through it to another portion of the window
	 we do not try to show a popover. We only want to show a popover if the
	 user has some intention of being in the list. */

	if (self.userPopoverMouseIsInView) {
		[self popUserInfoExpansionFrameAtPoint:self.userPopoverLastKnonwnLocalPoint ignoreTimerCheck:YES];
	}

	self.userPopoverTimerIsActive = NO;
}

#pragma mark -
#pragma mark Scroll View

- (void)awakeFromNib
{
	[RZNotificationCenter() addObserver:self
							   selector:@selector(scrollViewBoundsDidChangeNotification:)
								   name:NSViewBoundsDidChangeNotification
								 object:[self scrollViewContentView]];
	
	[self registerForDraggedTypes:@[NSFilenamesPboardType]];
}

- (void)scrollViewBoundsDidChangeNotification:(NSNotification *)aNote
{
	/* Only responds to events that are related to us… */
	if ([[aNote object] isEqual:[self scrollViewContentView]]) {
		/* Get current mouse position. */
		NSPoint mouseLocation = [NSEvent mouseLocation];

		NSRect fakeMouseLocation = NSMakeRect(mouseLocation.x, mouseLocation.y, 1, 1);

		NSRect rawPoint = [self.window convertRectFromScreen:fakeMouseLocation];

		NSPoint localPoint = [self convertPoint:rawPoint.origin fromView:nil];
		
		/* Handle popover. */
		[self popUserInfoExpansionFrameAtPoint:localPoint ignoreTimerCheck:YES];
	}
}

#pragma mark -
#pragma mark Drag and Drop

- (NSInteger)draggedRow:(id <NSDraggingInfo>)sender
{
    NSPoint p = [self convertPoint:[sender draggingLocation] fromView:nil];
	
    return [self rowAtPoint:p];
}

- (NSArray *)draggedFiles:(id <NSDraggingInfo>)sender
{
    return [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    return [self draggingUpdated:sender];
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    NSArray *files = [self draggedFiles:sender];
	
    if ([files count] > 0 && [self draggedRow:sender] >= 0) {
        return NSDragOperationCopy;
    } else {
        return NSDragOperationNone;
    }
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    NSArray *files = [self draggedFiles:sender];
	
    return ([files count] > 0 && [self draggedRow:sender] >= 0);
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSArray *files = [self draggedFiles:sender];
	
    if ([files count] > 0) {
        NSInteger row = [self draggedRow:sender];

        if (row >= 0) {
			[menuController() memberSendDroppedFiles:files row:@(row)];

            return YES;
        } else {
            return NO;
        }
    } else {
        return NO;
    }
}

#pragma mark -
#pragma mark Drawing Updates

- (void)updateDrawingForMember:(IRCUser *)cellItem
{
	PointerIsEmptyAssert(cellItem);
	
	NSInteger rowIndex = [self rowForItem:cellItem];
	
	NSAssertReturn(rowIndex >= 0);
	
	[self updateDrawingForRow:rowIndex];
}

#pragma mark -

- (void)reloadAllDrawings
{
	/* Reload drawings for all rows. */
	for (NSInteger i = 0; i < [self numberOfRows]; i++) {
		[self updateDrawingForRow:i];
	}
	
	/* Set display. */
	[self setNeedsDisplay:YES];
}

- (void)updateDrawingForRow:(NSInteger)rowIndex
{
	NSAssertReturn(rowIndex >= 0);
	
	id rowView = [self viewAtColumn:0 row:rowIndex makeIfNecessary:NO];
	
	[rowView updateDrawing];
}

- (BOOL)allowsVibrancy
{
	return YES;
}

- (NSScrollView *)scrollView
{
	return [self enclosingScrollView];
}

- (id)scrollViewContentView
{
	return [[self enclosingScrollView] contentView];
}

- (void)drawContextMenuHighlightForRow:(int)row
{
    // Do not draw focus ring …
}

- (void)drawBackgroundInClipRect:(NSRect)clipRect
{
	if ([self needsToDrawRect:clipRect]) {
		id userInterfaceObjects = [self userInterfaceObjects];
		
		NSColor *backgroundColor = [userInterfaceObjects memberListBackgroundColor];
		
		if (backgroundColor) {
			[backgroundColor set];
			
			NSRectFill(clipRect);
		} else {
			[super drawBackgroundInClipRect:clipRect];
		}
	}
}

- (id)userInterfaceObjects
{
	if ([CSFWSystemInformation featureAvailableToOSXYosemite]) {
		if ([TVCMemberListSharedUserInterface yosemiteIsUsingVibrantDarkMode] == NO) {
			return [TVCMemberListLightYosemiteUserInterface class];
		} else {
			return [TVCMemberListDarkYosemiteUserInterface class];
		}
	} else {
		return nil;
	}
}

- (void)updateBackgroundColor
{
	if ([CSFWSystemInformation featureAvailableToOSXYosemite]) {
		NSIndexSet *selectedRows = [self selectedRowIndexes];
		
		[self deselectAll:nil];
		
		if ([TPCPreferences invertSidebarColors]) {
			/* Source List style of NSOutlineView will actually ignore this appearance… that's
			 why we have self.visualEffectView behind it. However, we still set the appearance
			 so that the menu that inherits form it is dark. */
			[self setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
			
			[self.visualEffectView setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
		} else {
			[self setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantLight]];
		
			[self.visualEffectView setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantLight]];
		}
		
		[self selectRowIndexes:selectedRows byExtendingSelection:NO];
	}
}

@end

#pragma mark -
#pragma mark User Interface Design Elements

@implementation TVCMemberListSharedUserInterface

+ (BOOL)yosemiteIsUsingVibrantDarkMode
{
	NSVisualEffectView *visualEffectView = [mainWindowMemberList() visualEffectView];
	
	NSAppearance *currentDesign = [visualEffectView appearance];
	
	NSString *name = [currentDesign name];
	
	if ([name hasPrefix:NSAppearanceNameVibrantDark]) {
		return YES;
	} else {
		return NO;
	}
}

+ (NSColor *)memberListBackgroundColor
{
	id userInterfaceObjects = [mainWindowMemberList() userInterfaceObjects];
	
	if ([mainWindow() isInactive] || [mainWindow() isKeyWindow] == NO) {
		return [userInterfaceObjects memberListBackgroundColorForInactiveWindow];
	} else {
		return [userInterfaceObjects memberListBackgroundColorForActiveWindow];
	}
}

+ (NSColor *)userMarkBadgeBackgroundColor_YDefault // InspIRCd-2.0
{
	return [NSColor internalCalibratedRed:162 green:86 blue:58 alpha:1.0];
}

+ (NSColor *)userMarkBadgeBackgroundColor_QDefault
{
	return [NSColor internalCalibratedRed:186 green:0 blue:0 alpha:1.0];
}

+ (NSColor *)userMarkBadgeBackgroundColor_ADefault
{
	return [NSColor internalCalibratedRed:157 green:0 blue:89 alpha:1.0];
}

+ (NSColor *)userMarkBadgeBackgroundColor_ODefault
{
	return [NSColor internalCalibratedRed:90 green:51 blue:156 alpha:1.0];
}

+ (NSColor *)userMarkBadgeBackgroundColor_HDefault
{
	return [NSColor internalCalibratedRed:17 green:125 blue:19 alpha:1.0];
}

+ (NSColor *)userMarkBadgeBackgroundColor_VDefault
{
	return [NSColor internalCalibratedRed:51 green:123 blue:156 alpha:1.0];
}

+ (NSColor *)userMarkBadgeBackgroundColorWithAlphaCorrect:(NSString *)defaultsKey
{
	NSColor *defaultColor = [RZUserDefaults() colorForKey:defaultsKey];
	
	if ([CSFWSystemInformation featureAvailableToOSXYosemite]) {
		return [defaultColor colorWithAlphaComponent:0.7];
	} else {
		return  defaultColor;
	}
}

+ (NSColor *)userMarkBadgeBackgroundColor_Y // InspIRCd-2.0
{
	return [TVCMemberListSharedUserInterface userMarkBadgeBackgroundColorWithAlphaCorrect:@"User List Mode Badge Colors —> +y"];
}

+ (NSColor *)userMarkBadgeBackgroundColor_Q
{
	return [TVCMemberListSharedUserInterface userMarkBadgeBackgroundColorWithAlphaCorrect:@"User List Mode Badge Colors —> +q"];
}

+ (NSColor *)userMarkBadgeBackgroundColor_A
{
	return [TVCMemberListSharedUserInterface userMarkBadgeBackgroundColorWithAlphaCorrect:@"User List Mode Badge Colors —> +a"];
}

+ (NSColor *)userMarkBadgeBackgroundColor_O
{
	return [TVCMemberListSharedUserInterface userMarkBadgeBackgroundColorWithAlphaCorrect:@"User List Mode Badge Colors —> +o"];
}

+ (NSColor *)userMarkBadgeBackgroundColor_H
{
	return [TVCMemberListSharedUserInterface userMarkBadgeBackgroundColorWithAlphaCorrect:@"User List Mode Badge Colors —> +h"];
}

+ (NSColor *)userMarkBadgeBackgroundColor_V
{
	return [TVCMemberListSharedUserInterface userMarkBadgeBackgroundColorWithAlphaCorrect:@"User List Mode Badge Colors —> +v"];
}

+ (NSFont *)userMarkBadgeFont
{
	return [NSFont boldSystemFontOfSize:13.5];
}

+ (NSInteger)userMarkBadgeBottomMargin
{
	return 2.0;
}

+ (NSInteger)userMarkBadgeLeftMargin
{
	return 5.0;
}

+ (NSInteger)userMarkBadgeWidth
{
	return 20.0;
}

+ (NSInteger)userMarkBadgeHeight
{
	return 16.0;
}

+ (NSInteger)textCellLeftMargin
{
	return 29.0;
}

+ (NSInteger)textCellBottomMargin
{
	return 2.0;
}

@end

@implementation TVCMemberListMavericksUserInterface
@end

@implementation TVCMemberListLightYosemiteUserInterface

+ (NSColor *)userMarkBadgeBackgroundColorForActiveWindow
{
	return [NSColor colorWithCalibratedRed:0.232 green:0.232 blue:0.232 alpha:0.7];
}

+ (NSColor *)userMarkBadgeBackgroundColorForInactiveWindow
{
	return [NSColor colorWithCalibratedRed:0.232 green:0.232 blue:0.232 alpha:0.7];
}

+ (NSColor *)normalCellTextColorForActiveWindow
{
	return [NSColor colorWithCalibratedRed:0.232 green:0.232 blue:0.232 alpha:1.0];
}

+ (NSColor *)normalCellTextColorForInactiveWindow
{
	return [NSColor colorWithCalibratedRed:0.232 green:0.232 blue:0.232 alpha:1.0];
}

+ (NSColor *)awayUserCellTextColorForActiveWindow
{
	return [NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.5];
}

+ (NSColor *)awayUserCellTextColorForInactiveWindow
{
	return [NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.5];
}

+ (NSColor *)selectedCellTextColorForActiveWindow
{
	return [NSColor colorWithCalibratedWhite:1.0 alpha:1.0];
}

+ (NSColor *)selectedCellTextColorForInactiveWindow
{
	return [NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.5];
}

+ (NSColor *)userMarkBadgeNormalTextColor
{
	return [NSColor whiteColor];
}

+ (NSColor *)userMarkBadgeSelectedBackgroundColor
{
	return [NSColor whiteColor];
}

+ (NSColor *)userMarkBadgeSelectedTextColor
{
	return [NSColor colorWithCalibratedRed:0.232 green:0.232 blue:0.232 alpha:0.7];
}

+ (NSColor *)rowSelectionColorForActiveWindow
{
	return nil; // Use system default.
}

+ (NSColor *)rowSelectionColorForInactiveWindow
{
	return nil; // Use system default.
}

+ (NSColor *)memberListBackgroundColorForInactiveWindow
{
	return [NSColor clearColor]; // -clearColor informs receiver to disregard drawing entirely
}

+ (NSColor *)memberListBackgroundColorForActiveWindow
{
	return [NSColor clearColor];
}

@end

@implementation TVCMemberListDarkYosemiteUserInterface

+ (NSColor *)userMarkBadgeBackgroundColorForActiveWindow
{
	return [NSColor colorWithCalibratedRed:0.232 green:0.232 blue:0.232 alpha:0.7];
}

+ (NSColor *)userMarkBadgeBackgroundColorForInactiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.5 alpha:1.0];
}

+ (NSColor *)normalCellTextColorForActiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.8 alpha:1.0];
}

+ (NSColor *)awayUserCellTextColorForActiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.4 alpha:1.0];
}

+ (NSColor *)normalCellTextColorForInactiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.9 alpha:1.0];
}

+ (NSColor *)awayUserCellTextColorForInactiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
}

+ (NSColor *)selectedCellTextColorForActiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.7 alpha:1.0];
}

+ (NSColor *)selectedCellTextColorForInactiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.2 alpha:1.0];
}

+ (NSColor *)userMarkBadgeNormalTextColor
{
	return [NSColor whiteColor];
}

+ (NSColor *)userMarkBadgeSelectedBackgroundColor
{
	return [NSColor whiteColor];
}

+ (NSColor *)userMarkBadgeSelectedTextColor
{
	return [NSColor colorWithCalibratedRed:0.232 green:0.232 blue:0.232 alpha:1.0];
}

+ (NSColor *)rowSelectionColorForActiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.2 alpha:1.0];
}

+ (NSColor *)rowSelectionColorForInactiveWindow
{
	return [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
}

+ (NSColor *)memberListBackgroundColorForActiveWindow
{
	return [NSColor clearColor];
}

+ (NSColor *)memberListBackgroundColorForInactiveWindow
{
	return [NSColor colorWithCalibratedRed:0.248 green:0.248 blue:0.248 alpha:1.0];
}

@end
