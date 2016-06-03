//
//  AppDelegate.m
//  SoundcloudPlayer
//
//  Created by Philip Brechler on 20.06.14.
//  Copyright (c) 2014 Call a Nerd. All rights reserved.
//

#import "AppDelegate.h"
#import <SoundCloudAPI/SCAPI.h>
#import "SharedAudioPlayer.h"
#import "StreamCloudStyles.h"
#import "AFNetworking.h"
#import "TrackCellView.h"
#import "AppleMediaKeyController.h"
#import "SoundCloudAPIClient.h"
#import <HockeySDK/HockeySDK.h>
#import "AFNetworking.h"
#import "LastFm.h"

#import "MASShortcut+UserDefaults.h"
#import "MASShortcut+Monitoring.h"

#import "TrackCellForPlaylistItemView.h"
#import "SoundCloudPlaylist.h"
#import "SoundCloudUser.h"
#import "SoundCloudTrack.h"
#import "IsRepostedLabelView.h"


NSString *const PlayPauseShortcutPreferenceKey = @"PlayPauseShortcut";
NSString *const NextShortcutPreferenceKey = @"NextShortcut";
NSString *const PreviousShortcutPreferenceKey = @"PreviousShortcut";

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
 
#if IS_BETA
    [SCSoundCloud  setClientID:@"03c7205228575a03ec71606e083507af"
                        secret:@"b373772f7a7b030c23fc543c32e90eac"
                   redirectURL:[NSURL URLWithString:@"streamcloudbeta://soundcloud/callback"]];
#else
    [SCSoundCloud  setClientID:@"909c2edcdbd7b312b48a04a3f1e6b40c"
                        secret:@"bb9505cbb4c3f56e7926025e51a6371e"
                   redirectURL:[NSURL URLWithString:@"streamcloud://soundcloud/callback"]];
#endif
    
    
    AppleMediaKeyController *mkc = [AppleMediaKeyController sharedController];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(spaceBarPressed:) name:MediaKeyPlayPauseNotification object:mkc];
    [nc addObserver:self selector:@selector(leftKeyPressed:) name:MediaKeyPreviousNotification object:mkc];
    [nc addObserver:self selector:@selector(rightKeyPressed:) name:MediaKeyNextNotification object:mkc];
    
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(handleURLEvent:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSlider) name:@"SharedAudioPlayerUpdatedTimePlayed" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatePlayingItem) name:@"SharedPlayerDidFinishObject" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didGetNewSongs:) name:@"SoundCloudAPIClientDidLoadSongs" object:nil];
    id clipView = [[self.tableView enclosingScrollView] contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableViewDidScroll:) name:NSViewBoundsDidChangeNotification object:clipView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didFailToAuthenticate) name:@"SoundCloudAPIClientDidFailToAuthenticate" object:nil];
    
    [self.tableView setDoubleAction:@selector(tableViewDoubleClick)];
    
    
    [self.switchStreamLikesSegmentedControl setImage:[StreamCloudStyles imageOfIconTracksWithFrame:NSMakeRect(0, 0, 26, 24) active:YES] forSegment:0];
    [self.switchStreamLikesSegmentedControl setImage:[StreamCloudStyles imageOfIconFavoritesWithFrame:NSMakeRect(0, 0, 26, 24) active:NO] forSegment:1];

    
    if ([[SoundCloudAPIClient sharedClient] isLoggedIn]) {
        [[SoundCloudAPIClient sharedClient] getInitialStreamSongs];

    } else {
        [self didFailToAuthenticate];
    }
    
    
    [LastFm sharedInstance].apiKey = @"2473328884e701efe22e0491a9bbaeb6";
    [LastFm sharedInstance].apiSecret = @"8c197f07a45e251288815154a1569978";
    
    [[BITHockeyManager sharedHockeyManager] configureWithIdentifier:@"749b642d520ae57bfe9101ce28da075c"];
    [[BITHockeyManager sharedHockeyManager] startManager];
 
    
    [MASShortcut registerGlobalShortcutWithUserDefaultsKey:PlayPauseShortcutPreferenceKey handler:^{
        [self playButtonAction:nil];
    }];
    
    
    [MASShortcut registerGlobalShortcutWithUserDefaultsKey:NextShortcutPreferenceKey handler:^{
        [self nextButtonAction:nil];
    }];
        
    [MASShortcut registerGlobalShortcutWithUserDefaultsKey:PreviousShortcutPreferenceKey handler:^{
        [self previousButtonAction:nil];
    }];
    
    [self setCurrentlySelectedStream:CurrentSourceTypeStream];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag){
        [self.window makeKeyAndOrderFront:self];
    }
    return YES;
}

- (void)handleURLEvent:(NSAppleEventDescriptor*)event
        withReplyEvent:(NSAppleEventDescriptor*)replyEvent;
{
    NSString* url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    
    BOOL handled = [SCSoundCloud handleRedirectURL:[NSURL URLWithString:url]];
    if (!handled) {
        NSLog(@"The URL (%@) could not be handled by the SoundCloud API. Maybe you want to do something with it.", url);
    } else {
        [self.tableView.enclosingScrollView setHidden:NO];
        [[SoundCloudAPIClient sharedClient] getInitialStreamSongs];
        if (!self.statusBarPlayerViewController){
            // Status Item
            self.statusBarPlayerViewController = [[StatusBarPlayerViewController alloc] initWithNibName:@"StatusBarPlayerViewController" bundle:nil];
            NSImage *normalImageForStatusBar = [NSImage imageNamed:@"menuBarIcon"];
            [normalImageForStatusBar setTemplate:YES];
            NSImage *activeImageForStatusBar = [NSImage imageNamed:@"menuBarIcon_active"];
            [activeImageForStatusBar setTemplate:YES];
            self.statusItemPopup = [[AXStatusItemPopup alloc]initWithViewController:_statusBarPlayerViewController image:normalImageForStatusBar alternateImage:activeImageForStatusBar];
        }
    }
    
}


# pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([self sourceArrayForCurrentlySelectedStream].count > row){
        id itemForRow = [[self sourceArrayForCurrentlySelectedStream] objectAtIndex:row];
        NSString *identifier = [tableColumn identifier];
        if ([identifier isEqualToString:@"MainColumn"]){
            if ([itemForRow isKindOfClass:[SoundCloudTrack class]]) {
                SoundCloudTrack *trackForRow = itemForRow;
                if (!trackForRow.playlistTrackIsFrom) {
                    TrackCellView *viewforRow = [tableView makeViewWithIdentifier:@"MainCell" owner:self];
                    [viewforRow.artworkView.loadSpeakerOverlayView setHidden:YES];
                    [viewforRow.playingIndicatiorView setHidden:YES];
                    [viewforRow.artworkView setImage:nil];
                    [viewforRow setRow:row];
                    [viewforRow.artworkView setObjectToPlay:trackForRow];
                    
                    [viewforRow.artworkView loadArtworkImageWithURL:trackForRow.artworkUrl];
                    
                    [viewforRow.titleLabel setStringValue:trackForRow.title];
                    
                    [viewforRow.artistLabel setStringValue:trackForRow.user.username];
                    [viewforRow.artistLabel setUrlToOpen:trackForRow.user.permalinkUrl.absoluteString];
                    [viewforRow.artistLabel sizeToFit];
                    [viewforRow.artistLabel setAutoresizingMask:NSViewNotSizable];
                    
                    [viewforRow.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                        if ([obj isKindOfClass:[IsRepostedLabelView class]]){
                            [obj removeFromSuperview];
                        }
                    }];
                    if (trackForRow.repostedBy) {
                        IsRepostedLabelView *repostedLabelView = [[IsRepostedLabelView alloc]initWithFrame:NSMakeRect(viewforRow.artistLabel.frame.origin.x+viewforRow.artistLabel.frame.size.width+2, viewforRow.artistLabel.frame.origin.y+1, viewforRow.frame.size.width - viewforRow.artistLabel.frame.size.width- 77 - viewforRow.durationLabel.frame.size.width-16, 15)];
                        [viewforRow addSubview:repostedLabelView];
                        [repostedLabelView setReposterName:trackForRow.repostedBy.username];
                        [repostedLabelView setAutoresizingMask:NSViewWidthSizable];
                    }
                    
                    [viewforRow.durationLabel setStringValue:[self stringForSeconds:trackForRow.duration]];
                    
                    
                    if (itemForRow == [SharedAudioPlayer sharedPlayer].currentItem && [SharedAudioPlayer sharedPlayer].audioPlayer.rate) {
                        [viewforRow markAsPlaying:YES];
                    } else {
                        [viewforRow markAsPlaying:NO];
                    }
                    
                    // Shadows for Playlists only!
                    
                    viewforRow.seperatorView.hidden = NO;
                    
                    return viewforRow;
                } else {
                    TrackCellForPlaylistItemView *viewforRow = [tableView makeViewWithIdentifier:@"PlayListItemCell" owner:self];
                    [viewforRow setRow:row];
                    [viewforRow.artworkView setObjectToPlay:trackForRow];
                    [viewforRow.artworkView setImage:nil];
                    [viewforRow.artworkView.loadSpeakerOverlayView setHidden:YES];
                    [viewforRow.playingIndicatiorView setHidden:YES];
                    
                    [viewforRow.artworkView loadArtworkImageWithURL:trackForRow.artworkUrl];
                    
                    [viewforRow.titleLabel setStringValue:trackForRow.title];
                    [viewforRow.artistLabel setStringValue:trackForRow.user.username];
                    [viewforRow.artistLabel setUrlToOpen:trackForRow.user.permalinkUrl.absoluteString];
                    [viewforRow.artistLabel sizeToFit];
                    [viewforRow.artistLabel setAutoresizingMask:NSViewNotSizable];
                    [viewforRow.durationLabel setStringValue:[self stringForSeconds:trackForRow.duration]];
                    
                    if (itemForRow == [SharedAudioPlayer sharedPlayer].currentItem && [SharedAudioPlayer sharedPlayer].audioPlayer.rate) {
                        [viewforRow markAsPlaying:YES];
                    } else {
                        [viewforRow markAsPlaying:NO];
                    }
                    
                    // Showing shadows for first and last row
                    
                    viewforRow.upperShadowView.hidden = YES;
                    viewforRow.lowerShadowView.hidden = YES;
                    viewforRow.seperatorView.hidden = NO;

                    SoundCloudPlaylist *playlistForTrack = trackForRow.playlistTrackIsFrom;
                    NSArray *tracksOfPlaylistForTrack = playlistForTrack.tracks;
                    if (tracksOfPlaylistForTrack.firstObject == trackForRow) {
                        viewforRow.upperShadowView.hidden = NO;
                    } else if (tracksOfPlaylistForTrack.lastObject == trackForRow){
                        viewforRow.lowerShadowView.hidden = NO;
                        viewforRow.seperatorView.hidden = YES;
                    }
                    
                    return viewforRow;
                }
            } else if ([itemForRow isKindOfClass:[SoundCloudPlaylist class]]){
                SoundCloudPlaylist *playlistForRow = itemForRow;
                
                TrackCellView *viewforRow = [tableView makeViewWithIdentifier:@"MainCell" owner:self];
                [viewforRow.artworkView setImage:nil];
                [viewforRow setRow:row];
                [viewforRow.artworkView setObjectToPlay:itemForRow];
                [viewforRow.artworkView.loadSpeakerOverlayView setHidden:YES];
                [viewforRow.playingIndicatiorView setHidden:YES];
            
                [viewforRow.artworkView loadArtworkImageWithURL:playlistForRow.artworkUrl];
                
                [viewforRow.titleLabel setStringValue:playlistForRow.title];
                
                [viewforRow.artistLabel setStringValue:playlistForRow.user.username];
                [viewforRow.artistLabel setUrlToOpen:playlistForRow.user.permalinkUrl.absoluteString];
                [viewforRow.artistLabel sizeToFit];
                [viewforRow.artistLabel setAutoresizingMask:NSViewNotSizable];
                [viewforRow.durationLabel setStringValue:[self stringForSeconds:playlistForRow.duration]];
                
                [viewforRow.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    if ([obj isKindOfClass:[IsRepostedLabelView class]]){
                        [obj removeFromSuperview];
                    }
                }];
                
                if (playlistForRow.repostBy) {
                    IsRepostedLabelView *repostedLabelView = [[IsRepostedLabelView alloc]initWithFrame:NSMakeRect(viewforRow.artistLabel.frame.origin.x+viewforRow.artistLabel.frame.size.width+2, viewforRow.artistLabel.frame.origin.y+1, viewforRow.frame.size.width - viewforRow.artistLabel.frame.size.width- 77 - viewforRow.durationLabel.frame.size.width-16, 15)];
                    [viewforRow addSubview:repostedLabelView];
                    [repostedLabelView setReposterName:playlistForRow.repostBy.username];
                    [repostedLabelView setAutoresizingMask:NSViewWidthSizable];
                }
                
                if (itemForRow == [SharedAudioPlayer sharedPlayer].currentItem && [SharedAudioPlayer sharedPlayer].audioPlayer.rate) {
                    [viewforRow markAsPlaying:YES];
                } else {
                    [viewforRow markAsPlaying:NO];
                }
                
                // Hide seperator view for playlists
                
                viewforRow.seperatorView.hidden = YES;
                
                
                
                SoundCloudTrack *currentObject = [SharedAudioPlayer sharedPlayer].currentItem;
                if (currentObject.playlistTrackIsFrom == playlistForRow &&  [SharedAudioPlayer sharedPlayer].audioPlayer.rate) {
                    [viewforRow markAsPlaying:YES];
                } else {
                    [viewforRow markAsPlaying:NO];
                }
                
                return viewforRow;

            }
            
        }
    }
    return nil;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return NO;
}

- (void)tableView:(NSTableView *)tableView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
    if ([rowView isKindOfClass:[TrackCellView class]]){
        TrackCellView *viewForRow = (TrackCellView *)rowView;
        [viewForRow.artworkView setImage:nil];
    }
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    if ([self sourceArrayForCurrentlySelectedStream].count > row) {
        SoundCloudTrack *itemForRow = [[self sourceArrayForCurrentlySelectedStream] objectAtIndex:row];
        if ([itemForRow isKindOfClass:[SoundCloudTrack class]] && itemForRow.playlistTrackIsFrom) {
            return 40;
        } else {
            return 80;
        }
    } else {
        return 1;
    }
}
# pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [self sourceArrayForCurrentlySelectedStream].count;
}

# pragma mark - NSTableView Click Handling

- (void)tableViewDoubleClick {
    NSInteger clickedRow = [self.tableView clickedRow];
    if (_currentlySelectedStream == 0){
        [[SharedAudioPlayer sharedPlayer] switchToStream];
        id clickedItem = [[self sourceArrayForCurrentlySelectedStream] objectAtIndex:clickedRow];
        if ([clickedItem isKindOfClass:[SoundCloudPlaylist class]]){
            clickedItem = [[self sourceArrayForCurrentlySelectedStream] objectAtIndex:clickedRow+1];
        }
        
        NSInteger objectToPlay = [[[SharedAudioPlayer sharedPlayer] streamItemsToShowInTableView] indexOfObject:clickedItem];
        [[SharedAudioPlayer sharedPlayer] jumpToItemAtIndex:objectToPlay];
    } else if (_currentlySelectedStream == 1) {
        [[SharedAudioPlayer sharedPlayer] switchToFavorites];
        id clickedItem = [[self sourceArrayForCurrentlySelectedStream] objectAtIndex:clickedRow];
        NSInteger objectToPlay = [[[SharedAudioPlayer sharedPlayer] favoriteItemsToShowInTableView] indexOfObject:clickedItem];
        [[SharedAudioPlayer sharedPlayer] jumpToItemAtIndex:objectToPlay];
    }
}

# pragma mark - NSTableView Scroll Handling

-(void)tableViewDidScroll:(NSNotification *) notification
{
    NSScrollView *scrollView = [notification object];
    CGFloat currentPosition = CGRectGetMaxY([scrollView visibleRect]);
    CGFloat tableViewHeight = [self.tableView bounds].size.height - 100;
    
    //console.log("TableView Height: " + tableViewHeight);
    //console.log("Current Position: " + currentPosition);
    
    if ((currentPosition > tableViewHeight - 100) && !self.atBottom)
    {
        self.atBottom = YES;
        [[SharedAudioPlayer sharedPlayer] getNextSongs];
    } else if (currentPosition < tableViewHeight - 100) {
        self.atBottom = NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SongTableViewDidScroll" object:nil];
}

# pragma mark - Update UI 

- (void)updateSlider {
    float timeGone = CMTimeGetSeconds([SharedAudioPlayer sharedPlayer].audioPlayer.currentTime);
    float durationOfItem = CMTimeGetSeconds([SharedAudioPlayer sharedPlayer].audioPlayer.currentItem.duration);
    if (timeGone != NAN && timeGone != INFINITY && timeGone < DBL_MAX){
        [self.timeToGoLabel setStringValue:[self stringForSeconds:durationOfItem]];
        [self.timeGoneLabel setStringValue:[self stringForSeconds:timeGone]];
        if (!self.playerTimeSlider.clicked)
            [self.playerTimeSlider setDoubleValue:(timeGone/durationOfItem)*100];
    }
}

- (void)updatePlayingItem {
    
    [self.statusBarPlayerViewController reloadImage];
    
    [self.tableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
        [rowView setBackgroundColor:[NSColor whiteColor]];
        TrackCellView *cellForRow = [rowView viewAtColumn:0];
        [cellForRow markAsPlaying:NO];
    }];
    SoundCloudTrack *currentItem = [SharedAudioPlayer sharedPlayer].currentItem;
    if (currentItem) {
        NSUInteger rowForItem = [[self sourceArrayForCurrentlySelectedStream] indexOfObject:currentItem];
        NSLog(@"Now playing song in row %lu",(unsigned long)rowForItem);
        if (rowForItem != NSNotFound && rowForItem < self.tableView.numberOfRows){
            NSTableRowView *rowView = [self.tableView rowViewAtRow:rowForItem makeIfNecessary:NO];
            [rowView setBackgroundColor:[StreamCloudStyles grayLight]];
            TrackCellView *cellForRow = [self.tableView viewAtColumn:0 row:rowForItem makeIfNecessary:NO];
            if (cellForRow){
                [cellForRow markAsPlaying:YES];
            }
            if (currentItem.playlistTrackIsFrom) {
                SoundCloudPlaylist *playlistTrackIsFrom = currentItem.playlistTrackIsFrom;
                NSUInteger rowForPlaylist = [[self sourceArrayForCurrentlySelectedStream] indexOfObject:playlistTrackIsFrom];
                NSLog(@"Marking playlist row %lu",(unsigned long)rowForPlaylist);
                NSTableRowView *playlistRowView = [self.tableView rowViewAtRow:rowForPlaylist makeIfNecessary:NO];
                [playlistRowView setBackgroundColor:[StreamCloudStyles grayLight]];
                TrackCellView *cellForPlaylistRow = [self.tableView viewAtColumn:0 row:rowForPlaylist makeIfNecessary:NO];
                if (cellForPlaylistRow){
                    [cellForPlaylistRow markAsPlaying:YES];
                }
                
            }
            [self.tableView scrollRowToVisible:rowForItem];
            [self.trackNameDockMenuItem setTitle:[NSString stringWithFormat:@"%@ - %@",currentItem.title,currentItem.user.username]];
        }
    }
}

- (void)didGetNewSongs:(NSNotification *)notification {
    if (notification.object) {
        NSDictionary *notificationObject = notification.object;
        NSString *insertedIn = [notificationObject objectForKey:@"type"];
        NSNumber *countOfNewObject = [notificationObject objectForKey:@"count"];
        if (countOfNewObject > 0) {
            [self.tableView beginUpdates];
            if ([insertedIn isEqualToString:@"stream"] && self.currentlySelectedStream == 0) {
                NSIndexSet *insertIndexSet = [[NSIndexSet alloc]initWithIndexesInRange:NSMakeRange(self.tableView.numberOfRows, [countOfNewObject doubleValue])];
                [self.tableView insertRowsAtIndexes:insertIndexSet withAnimation:NSTableViewAnimationEffectFade];
            } else if ([insertedIn isEqualToString:@"favorites"] && self.currentlySelectedStream == 1) {
                NSIndexSet *insertIndexSet = [[NSIndexSet alloc]initWithIndexesInRange:NSMakeRange(self.tableView.numberOfRows, [countOfNewObject doubleValue])];
                [self.tableView insertRowsAtIndexes:insertIndexSet withAnimation:NSTableViewAnimationEffectFade];
            }
            [self.tableView endUpdates];
        }
    } else {
        [self.tableView reloadData];
    }
    if (!self.statusItemPopup){
        // Status Item
        self.statusBarPlayerViewController = [[StatusBarPlayerViewController alloc] initWithNibName:@"StatusBarPlayerViewController" bundle:nil];
        NSImage *normalImageForStatusBar = [NSImage imageNamed:@"menuBarIcon"];;
        NSImage *activeImageForStatusBar = [NSImage imageNamed:@"menuBarIcon_active"];
        self.statusItemPopup = [[AXStatusItemPopup alloc]initWithViewController:_statusBarPlayerViewController image:normalImageForStatusBar alternateImage:activeImageForStatusBar];
    }
    if ([self sourceArrayForCurrentlySelectedStream].count == 0 && [[SoundCloudAPIClient sharedClient] isLoggedIn]){
        [self.tableView.enclosingScrollView setHidden:YES];
        [self.loginButton setHidden:YES];
        [self.loginTextField setStringValue:NSLocalizedString(@"Follow some people or like some tracks on SoundCloud to see them here",nil)];
    } else {
        [self.tableView.enclosingScrollView setHidden:NO];
        [self.loginButton setHidden:NO];
        [self.loginTextField setStringValue:NSLocalizedString(@"Connect with SoundCloud® to get your Stream", nil)];
    }
}

- (void)didFailToAuthenticate {
    [self.tableView.enclosingScrollView setHidden:YES];
    [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItemPopup.statusItem];
    self.statusItemPopup = nil;
    self.statusBarPlayerViewController = nil;
}

# pragma mark - Hotkeys

- (void)spaceBarPressed:(NSEvent *)event {
    [self playButtonAction:nil];
}

- (void)leftKeyPressed:(NSEvent *)event {
    [self previousButtonAction:nil];
}

- (void)rightKeyPressed:(NSEvent *)event {
    [self nextButtonAction:nil];
}

# pragma mark - IBActions

- (IBAction)playButtonAction:(id)sender {
    [[SharedAudioPlayer sharedPlayer] togglePlayPause];
}

- (IBAction)previousButtonAction:(id)sender {
    [[SharedAudioPlayer sharedPlayer] previousItem];
}

- (IBAction)nextButtonAction:(id)sender {
    [[SharedAudioPlayer sharedPlayer] nextItem];
}

- (IBAction)shuffleButtonAction:(id)sender {
    [[SharedAudioPlayer sharedPlayer] setShuffleEnabled:![SharedAudioPlayer sharedPlayer].shuffleEnabled];
}

- (IBAction)sliderUpdate:(id)sender {
    float durationOfItem = CMTimeGetSeconds([SharedAudioPlayer sharedPlayer].audioPlayer.currentItem.duration);
    double newValue = self.playerTimeSlider.doubleValue;
    float newTime = (newValue/100)*durationOfItem;
    NSLog(@"Seeking to time %f.0",newTime);
    [[SharedAudioPlayer sharedPlayer] advanceToTime:newTime];
}

- (IBAction)volumeSliderUpdate:(id)sender {
    [[SharedAudioPlayer sharedPlayer].audioPlayer setVolume:self.playerVolumeSlider.doubleValue/100];
    [self.volumeButton.cell setEnabled:NO];
    [self.volumeButton.cell setEnabled:YES];
}

- (IBAction)volumeButtonAction:(id)sender {
    [self.playerVolumeSlider setDoubleValue:[SharedAudioPlayer sharedPlayer].audioPlayer.volume*100];
    if (self.volumePopover.isShown){
        [self.volumePopover close];
    } else {
        [self.volumePopover showRelativeToRect:self.volumeButton.bounds ofView:self.volumeButton preferredEdge:NSMaxYEdge];
    }
}

- (IBAction)repeatButtonAction:(id)sender {
    [[SharedAudioPlayer sharedPlayer] toggleRepeatMode];
}

- (IBAction)loginButtonAction:(id)sender {
    [[SoundCloudAPIClient sharedClient] login];
}

- (IBAction)logoutMenuAction:(id)sender {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    [[SoundCloudAPIClient sharedClient] logout];
}

- (IBAction)reloadMenuAction:(id)sender {
    [[SoundCloudAPIClient sharedClient] reloadStream];
}

- (IBAction)showAboutMenuAction:(id)sender {
    [self.aboutPanel makeKeyAndOrderFront:sender];
}

- (IBAction)showSettingsMenuAction:(id)sender {
    [self.settingsPanel makeKeyAndOrderFront:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MainWindowOpenSettings" object:nil];
}

- (IBAction)openWebsiteFromHelpMenuAction:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://streamcloud.cc"]];
}

- (IBAction)switchStreamLikesChangedAction:(id)sender {
    [self setCurrentlySelectedStream:self.switchStreamLikesSegmentedControl.selectedSegment];
    if (self.switchStreamLikesSegmentedControl.selectedSegment == 0){
        [self.switchStreamLikesSegmentedControl setImage:[StreamCloudStyles imageOfIconTracksWithFrame:NSMakeRect(0, 0, 26, 24) active:YES] forSegment:0];
        [self.switchStreamLikesSegmentedControl setImage:[StreamCloudStyles imageOfIconFavoritesWithFrame:NSMakeRect(0, 0, 26, 24) active:NO] forSegment:1];
    } else {
        [self.switchStreamLikesSegmentedControl setImage:[StreamCloudStyles imageOfIconTracksWithFrame:NSMakeRect(0, 0, 26, 24) active:NO] forSegment:0];
        [self.switchStreamLikesSegmentedControl setImage:[StreamCloudStyles imageOfIconFavoritesWithFrame:NSMakeRect(0, 0, 26, 24) active:YES] forSegment:1];
    }
}

# pragma mark - Window managment

- (void)windowWillClose:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MainWindowCloseSettings" object:nil];
}
# pragma mark - Helpers

- (NSString *)stringForSeconds:(NSTimeInterval)elapsedSeconds {
    NSInteger ti = (NSInteger)elapsedSeconds;
    NSInteger seconds = ti % 60;
    NSInteger minutes = (ti / 60) % 60;
    NSInteger hours = (ti / 3600);
    
    if (hours > 0)
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    else
        return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
}

- (NSMutableArray *)sourceArrayForCurrentlySelectedStream {
    if (_currentlySelectedStream == 0) {
        return [[SharedAudioPlayer sharedPlayer] streamItemsToShowInTableView];
    } else {
        return [[SharedAudioPlayer sharedPlayer] favoriteItemsToShowInTableView];
    }
}

# pragma mark - Custom Setters

- (void)setCurrentlySelectedStream:(NSInteger)currentlySelectedStream {
    if (_currentlySelectedStream != currentlySelectedStream){
        _currentlySelectedStream = currentlySelectedStream;
        [[SharedAudioPlayer sharedPlayer] setSourceType:currentlySelectedStream];
        [self.tableView reloadData];
        if (_currentlySelectedStream == 1 && [self sourceArrayForCurrentlySelectedStream].count <= 0) {
            [[SoundCloudAPIClient sharedClient] getInitialFavoriteSongs];
        }
    }
}

@end
