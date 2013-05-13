//
//  PortalKeysViewController.m
//  Ingress
//
//  Created by Alex Studnicka on 18.01.13.
//  Copyright (c) 2013 A&A Code. All rights reserved.
//

#import "PortalKeysViewController.h"
#import <SDWebImage/UIImageView+WebCache.h>

@implementation PortalKeysViewController {
	NSMutableDictionary *keysDict;
	NSMutableArray *portals;

	PortalKey *currentPortalKey;
}

@synthesize linkingPortal = _linkingPortal;

- (void)viewDidLoad {
	[super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	if (self.linkingPortal) {
		self.navigationItem.title = @"Select Portal Key";
	}

	[self refresh];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];

}

- (void)refresh {

	NSArray *fetchedKeys = [PortalKey MR_findAllWithPredicate:[NSPredicate predicateWithFormat:@"dropped = NO"]];
	keysDict = [NSMutableDictionary dictionary];
	for (PortalKey *portalKey in fetchedKeys) {
		if ([keysDict.allKeys containsObject:portalKey.portal.guid]) {
			NSMutableArray *array = keysDict[portalKey.portal.guid];
			[array addObject:portalKey];
		} else {
			keysDict[portalKey.portal.guid] = [NSMutableArray arrayWithObject:portalKey];
		}
	}

	portals = [NSMutableArray arrayWithCapacity:keysDict.allKeys.count];
	for (NSString *portalGuid in keysDict.allKeys) {
		[portals addObject:[Portal MR_findFirstByAttribute:@"guid" withValue:portalGuid]];
	}

	[portals sortUsingComparator:^NSComparisonResult(Portal *obj1, Portal *obj2) {
		CLLocationDistance dist1 = [obj1 distanceFromCoordinate:[AppDelegate instance].mapView.centerCoordinate];
		CLLocationDistance dist2 = [obj2 distanceFromCoordinate:[AppDelegate instance].mapView.centerCoordinate];

		if (dist1 < dist2) {
			return NSOrderedAscending;
		} else if (dist1 > dist2) {
			return NSOrderedDescending;
		} else {
			return NSOrderedSame;
		}
	}];

	[self.tableView reloadData];

}

#pragma mark - UITableViewDataSource & UITableViewDelegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return portals.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PortalKeyCell" forIndexPath:indexPath];

	Portal *portal = portals[indexPath.row];
	int numberOfPortals = [keysDict[portal.guid] count];
    cell.textLabel.text = [NSString stringWithFormat:@"%dx %@", numberOfPortals, portal.subtitle];
	cell.detailTextLabel.text = portal.address;

//	if ([@[@"ALIENS", @"RESISTANCE"] containsObject:portal.controllingTeam]) {
//		cell.textLabel.textColor = [API colorForFaction:portal.controllingTeam];
//	} else {
	cell.textLabel.textColor = [UIColor whiteColor];
//	}

	[cell.imageView setImageWithURL:[NSURL URLWithString:portal.imageURL] placeholderImage:[UIImage imageNamed:@"missing_image"]];

    return cell;
	
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];

	if (self.linkingPortal) {

		[[API sharedInstance] playSound:@"SPEECH_ESTABLISHING_PORTAL_LINK"];

		__block MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
		HUD.userInteractionEnabled = YES;
		HUD.dimBackground = YES;
		HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
		HUD.labelText = @"Querying Linkability...";
		[[AppDelegate instance].window addSubview:HUD];
		[HUD show:YES];

		Portal *portal = portals[indexPath.row];
		PortalKey *portalKey = [keysDict[portal.guid] lastObject];

		[[API sharedInstance] queryLinkabilityForPortal:self.linkingPortal portalKey:portalKey completionHandler:^(NSString *errorStr) {

			[HUD hide:YES];

			if (errorStr) {
				HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
				HUD.userInteractionEnabled = YES;
				HUD.dimBackground = YES;
				HUD.mode = MBProgressHUDModeCustomView;
				HUD.customView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"warning.png"]];
				HUD.detailsLabelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
				HUD.detailsLabelText = errorStr;
				[[AppDelegate instance].window addSubview:HUD];
				[HUD show:YES];
				[HUD hide:YES afterDelay:3];
			} else {

				HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
				HUD.userInteractionEnabled = YES;
				HUD.dimBackground = YES;
				HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
				HUD.labelText = @"Linking Portal...";
				[[AppDelegate instance].window addSubview:HUD];
				[HUD show:YES];

				[[API sharedInstance] linkPortal:self.linkingPortal withPortalKey:portalKey completionHandler:^(NSString *errorStr) {

					[HUD hide:YES];

					if (errorStr) {
						HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
						HUD.userInteractionEnabled = YES;
						HUD.dimBackground = YES;
						HUD.mode = MBProgressHUDModeCustomView;
						HUD.customView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"warning.png"]];
						HUD.detailsLabelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
						HUD.detailsLabelText = errorStr;
						[[AppDelegate instance].window addSubview:HUD];
						[HUD show:YES];
						[HUD hide:YES afterDelay:3];
					} else {

						[[API sharedInstance] playSound:@"SPEECH_PORTAL_LINK_ESTABLISHED"];

					}

					[self refresh];
					
				}];

			}

		}];
		
	} else {

		Portal *portal = portals[indexPath.row];
		PortalKey *portalKey = [keysDict[portal.guid] lastObject];
		currentPortalKey = portalKey;

		UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Drop" otherButtonTitles:@"Recharge Portal", nil];
		actionSheet.tag = 1;
		[actionSheet showFromTabBar:self.tabBarController.tabBar];

	}

}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];
	if (actionSheet.tag == 1 && buttonIndex == 0) {

		__block MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
		HUD.userInteractionEnabled = YES;
		HUD.mode = MBProgressHUDModeIndeterminate;
		HUD.dimBackground = YES;
		HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
		HUD.labelText = @"Dropping Portal Key...";
		[[AppDelegate instance].window addSubview:HUD];
		[HUD show:YES];

		[[API sharedInstance] playSound:@"SFX_DROP_RESOURCE"];

		[[API sharedInstance] dropItemWithGuid:currentPortalKey.guid completionHandler:^(void) {
			[HUD hide:YES];

			[self refresh];
		}];

	} else if (actionSheet.tag == 1 && buttonIndex == 1) {

		PortalKey *portalKey = currentPortalKey;

		__block MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
		HUD.userInteractionEnabled = YES;
		HUD.mode = MBProgressHUDModeIndeterminate;
		HUD.dimBackground = YES;
		HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
		HUD.labelText = @"Recharging Portal...";
		[[AppDelegate instance].window addSubview:HUD];
		[HUD show:YES];

		[[API sharedInstance] playSound:@"SFX_RESONATOR_RECHARGE"];

		[[API sharedInstance] remoteRechargePortal:portalKey.portal portalKey:portalKey completionHandler:^(NSString *errorStr) {

			[HUD hide:YES];

			if (errorStr) {

				MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
				HUD.userInteractionEnabled = YES;
				HUD.dimBackground = YES;
				HUD.mode = MBProgressHUDModeCustomView;
				HUD.customView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"warning.png"]];
				HUD.detailsLabelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
				HUD.detailsLabelText = errorStr;
				[[AppDelegate instance].window addSubview:HUD];
				[HUD show:YES];
				[HUD hide:YES afterDelay:3];

			} else {
				[[API sharedInstance] playSounds:@[@"SPEECH_RESONATOR", @"SPEECH_RECHARGED"]];
			}

			currentPortalKey = nil;

		}];

	}
}

@end
