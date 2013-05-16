//
//  ViewController.m
//  Ingress
//
//  Created by Alex Studnicka on 08.01.13.
//  Copyright (c) 2013 A&A Code. All rights reserved.
//

#import "ScannerViewController.h"
#import "PortalDetailViewController.h"
#import "MissionViewController.h"
#import "MKMapView+ZoomLevel.h"

#import "PortalOverlayView.h"
#import "MKPolyline+PortalLink.h"
#import "MKPolygon+ControlField.h"
#import "MKCircle+Ingress.h"
#import "DeployedResonatorView.h"
#import "XMOverlayView.h"
#import "XMOverlay.h"

@implementation ScannerViewController {

	Portal *currentPortal;
	Item *currentItem;

	UIView *rangeCircleView;
	CLLocationManager *locationManager;
	CLLocation *lastLocation;
	BOOL firstRefreshProfile;
	BOOL firstLocationUpdate;
	BOOL portalDetailSegue;
	MBProgressHUD *locationAllowHUD;
    XMOverlay *_xmOverlay;
    XMOverlayView *_xmOverlayView;

	NSTimer *refreshTimer;

	NSMutableSet *mapGuids;

}

- (void)viewDidLoad {
    [super viewDidLoad];

	[ControlField MR_truncateAll];
	[PortalLink MR_truncateAll];
	[Item MR_deleteAllMatchingPredicate:[NSPredicate predicateWithFormat:@"dropped = YES"]];
	[EnergyGlob MR_truncateAll];
	[DeployedResonator MR_truncateAll];
	[DeployedMod MR_truncateAll];

	mapGuids = [NSMutableSet set];

	[[AppDelegate instance] setMapView:_mapView];

	levelLabel.font = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:32];
	nicknameLabel.font = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:20];
	apLabel.font = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:20];
	xmLabel.font = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:20];

	apLabel.hidden = YES;
	xmLabel.hidden = YES;
	apLabel.alpha = 0;
	xmLabel.alpha = 0;

	firstRefreshProfile = YES;
	firstLocationUpdate = YES;

	[xmIndicator setProgressImage:[[UIImage imageNamed:@"progressImage-aliens.png"] resizableImageWithCapInsets:UIEdgeInsetsMake(7, 7, 7, 7)]];
	[xmIndicator setTrackImage:[[UIImage imageNamed:@"trackImage.png"] resizableImageWithCapInsets:UIEdgeInsetsMake(2, 2, 2, 2)]];

	rangeCircleView = [UIView new];
	rangeCircleView.frame = CGRectMake(0, 0, 0, 0);
	rangeCircleView.center = _mapView.center;
	rangeCircleView.backgroundColor = [UIColor clearColor];
	rangeCircleView.opaque = NO;
	rangeCircleView.userInteractionEnabled = NO;
	rangeCircleView.layer.cornerRadius = 0;
	rangeCircleView.layer.masksToBounds = YES;
	rangeCircleView.layer.borderWidth = 2;
	rangeCircleView.layer.borderColor = [[[UIColor blueColor] colorWithAlphaComponent:0.25] CGColor];
	[self.view addSubview:rangeCircleView];

	[NSTimer scheduledTimerWithTimeInterval:.01 target:self selector:@selector(updateCircle) userInfo:nil repeats:YES];

	locationManager = [[CLLocationManager alloc] init];
    locationManager.delegate = self;
    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
	if ([locationManager respondsToSelector:@selector(activityType)]) {
		locationManager.activityType = CLActivityTypeFitness;
	}
	
	[locationManager startUpdatingLocation];
	[locationManager startUpdatingHeading];

	UIPinchGestureRecognizer *recognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
	[_mapView addGestureRecognizer:recognizer];

	#ifdef DEBUG
	#warning Manual scrolling for debug purposes only!
	UITapGestureRecognizer *mapViewTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mapTapped:)];
	mapViewTapGestureRecognizer.numberOfTapsRequired = 2;
	[_mapView addGestureRecognizer:mapViewTapGestureRecognizer];
	#endif

	UILongPressGestureRecognizer *mapViewLognPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapLongPress:)];
	[_mapView addGestureRecognizer:mapViewLognPressGestureRecognizer];

    _xmOverlay = [XMOverlay new];
    [_mapView addOverlay:_xmOverlay];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	[self.navigationController setNavigationBarHidden:YES animated:YES];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextObjectsDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserverForName:@"ProfileUpdatedNotification" object:nil queue:[[API sharedInstance] notificationQueue] usingBlock:^(NSNotification *note) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self refreshProfile];
		});
	}];

	[self refreshProfile];

}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	
//	CALayer *layer = _mapView.layer;
//	CATransform3D transform = CATransform3DIdentity;
//	transform.m34 = -0.002;
//	transform = CATransform3DRotate(transform, 45 * M_PI / 180, 1, 0, 0);
//	transform = CATransform3DTranslate(transform, 0, 0, 100);
//	transform = CATransform3DScale(transform, 2, 2, 2);
//	layer.transform = transform;
//	layer.shouldRasterize = YES;

	if ([[[API sharedInstance] playerInfo][@"allowFactionChoice"] boolValue]) {
		[self performSegueWithIdentifier:@"FactionChooseSegue" sender:self];
	}
	
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];

	if (portalDetailSegue) {
		[self.navigationController setNavigationBarHidden:NO animated:YES];
	}
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Data Refresh

- (void)refresh {

//	if (refreshTimer) {
//		[refreshTimer invalidate];
//		refreshTimer = nil;
//	}
//	refreshTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(refresh) userInfo:nil repeats:NO];

	[_mapView removeAnnotations:_mapView.annotations];

	NSMutableArray *overlays = [_mapView.overlays mutableCopy];
    [overlays removeObject:_xmOverlay];
	[_mapView removeOverlays:overlays];

	[[API sharedInstance] getObjectsWithCompletionHandler:nil];
}

- (void)refreshProfile {

	NSDictionary *playerInfo = [[API sharedInstance] playerInfo];

	int ap = [playerInfo[@"ap"] intValue];
	int level = [API levelForAp:ap];
	int maxAp = [API maxApForLevel:level];
	float energy = [playerInfo[@"energy"] floatValue];
	float maxEnergy = [API maxXmForLevel:level];

	[apLabel setText:[NSString stringWithFormat:@"%d AP", ap]];
	[xmLabel setText:[NSString stringWithFormat:@"%d XM", (int)energy]];

	NSMutableParagraphStyle *pStyle = [NSMutableParagraphStyle new];
    pStyle.alignment = NSTextAlignmentRight;

	UIColor *teamColor = [API colorForFaction:playerInfo[@"team"]];
	
	[apView setFaction:playerInfo[@"team"]];
	NSArray *maxAPs = @[@0, @10000, @30000, @70000, @150000, @300000, @600000, @1200000, @(INFINITY)];
	[apView setProgress:(maxAp == 0 ? 0 : ((ap - [maxAPs[level - 1] floatValue]) / ([maxAPs[level] floatValue] - [maxAPs[level - 1] floatValue])))];

	levelLabel.text = [NSString stringWithFormat:@"%d", level];

	nicknameLabel.textColor = teamColor;
	nicknameLabel.text = playerInfo[@"nickname"];

	if ([[API sharedInstance].playerInfo[@"team"] isEqualToString:@"RESISTANCE"]) {
		[xmIndicator setProgressImage:[[UIImage imageNamed:@"progressImage-resistance.png"] resizableImageWithCapInsets:UIEdgeInsetsMake(7, 7, 7, 7)]];
	} else {
		[xmIndicator setProgressImage:[[UIImage imageNamed:@"progressImage-aliens.png"] resizableImageWithCapInsets:UIEdgeInsetsMake(7, 7, 7, 7)]];
	}

	[xmIndicator setProgress:(energy/maxEnergy) animated:!firstRefreshProfile];

	firstRefreshProfile = NO;

}

#pragma mark - IBActions

- (IBAction)showAP {
	if (apLabel.hidden) {
		[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];
		
		[apLabel setHidden:NO];
		[UIView animateWithDuration:.5 animations:^{
			[apLabel setAlpha:1];
		}];
		[UIView animateWithDuration:.5 delay:2 options:0 animations:^{
			[apLabel setAlpha:0];
		} completion:^(BOOL finished) {
			[apLabel setHidden:YES];
		}];
	}
}

- (IBAction)showXM {
	if (xmLabel.hidden) {
		[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];

		[xmLabel setHidden:NO];
		[UIView animateWithDuration:.5 animations:^{
			[xmLabel setAlpha:1];
		}];
		[UIView animateWithDuration:.5 delay:2 options:0 animations:^{
			[xmLabel setAlpha:0];
		} completion:^(BOOL finished) {
			[xmLabel setHidden:YES];
		}];
	}
}

#pragma mark - Map Data Managing

- (void)insertObjectToMapView:(NSManagedObject *)object {

	MKMapRect mapRect = MKMapRectWorld; //MKMapRectOffset(_mapView.visibleMapRect, 1024, 1024);
	
	if ([object isKindOfClass:[Portal class]]) {
		Portal *portal = (Portal *)object;
		if (![mapGuids containsObject:portal.guid] && MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate(portal.coordinate))) {
			[mapGuids addObject:portal.guid];
			dispatch_async(dispatch_get_main_queue(), ^{
				[_mapView addOverlay:portal];
				[_mapView addAnnotation:portal];
			});
		}
//	} else if ([object isKindOfClass:[EnergyGlob class]]) {
//		EnergyGlob *xm = (EnergyGlob *)object;
//		if (![mapGuids containsObject:xm.guid] && MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate(xm.coordinate))) {
//			[mapGuids addObject:xm.guid];
////			NSLog(@"XM %@ (%d) adding", xm.guid, xm.amount);
//			dispatch_async(dispatch_get_main_queue(), ^{
//				[_mapView addOverlay:xm.circle];
//			});
//		}
	} else if ([object isKindOfClass:[Item class]] && ![object isKindOfClass:[EnergyGlob class]]) {
		Item *item = (Item *)object;
		if (![mapGuids containsObject:item.guid] && MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate(item.coordinate))) {
			[mapGuids addObject:item.guid];
			dispatch_async(dispatch_get_main_queue(), ^{
				[_mapView addAnnotation:item];
			});
		}
	} else if ([object isKindOfClass:[PortalLink class]]) {
		PortalLink *portalLink = (PortalLink *)object;
		if (![mapGuids containsObject:portalLink.guid] && (MKMapRectIntersectsRect(mapRect, portalLink.polyline.boundingMapRect) || MKMapRectContainsRect(_mapView.visibleMapRect, portalLink.polyline.boundingMapRect))) {
			[mapGuids addObject:portalLink.guid];
			dispatch_async(dispatch_get_main_queue(), ^{
				[_mapView addOverlay:portalLink.polyline];
			});
		}
	} else if ([object isKindOfClass:[ControlField class]]) {
		ControlField *controlField = (ControlField *)object;
		if (![mapGuids containsObject:controlField.guid] && (MKMapRectIntersectsRect(mapRect, controlField.polygon.boundingMapRect) || MKMapRectContainsRect(_mapView.visibleMapRect, controlField.polygon.boundingMapRect))) {
			[mapGuids addObject:controlField.guid];
			dispatch_async(dispatch_get_main_queue(), ^{
				[_mapView addOverlay:controlField.polygon];
			});
		}
	} else if ([object isKindOfClass:[DeployedResonator class]]) {
		DeployedResonator *resonator = (DeployedResonator *)object;
		NSString *resonatorGuid = [NSString stringWithFormat:@"%@-%d", resonator.portal.guid, resonator.slot];
		if (![mapGuids containsObject:resonatorGuid] && MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate(resonator.circle.coordinate))) {
			[mapGuids addObject:resonatorGuid];
			dispatch_async(dispatch_get_main_queue(), ^{
				[_mapView addOverlay:resonator.circle];
			});
		}
	}
	
}

- (void)removeObjectFromMapView:(NSManagedObject *)object {
	
	if ([object isKindOfClass:[Portal class]]) {
		Portal *portal = (Portal *)object;
		[mapGuids removeObject:portal.guid];
		dispatch_async(dispatch_get_main_queue(), ^{
			[_mapView removeOverlay:portal];
			[_mapView removeAnnotation:portal];
		});
//	} else if ([object isKindOfClass:[EnergyGlob class]]) {
//		EnergyGlob *xm = (EnergyGlob *)object;
//		[mapGuids removeObject:xm.guid];
//		NSLog(@"XM %@ (%d) removing", xm.guid, xm.amount);
//		dispatch_async(dispatch_get_main_queue(), ^{
//			[_mapView removeOverlay:xm.circle];
//		});
	} else if ([object isKindOfClass:[Item class]] && ![object isKindOfClass:[EnergyGlob class]]) {
		Item *item = (Item *)object;
		[mapGuids removeObject:item.guid];
		dispatch_async(dispatch_get_main_queue(), ^{
			[_mapView removeAnnotation:item];
		});
	} else if ([object isKindOfClass:[PortalLink class]]) {
		PortalLink *portalLink = (PortalLink *)object;
		[mapGuids removeObject:portalLink.guid];
		dispatch_async(dispatch_get_main_queue(), ^{
			[_mapView removeOverlay:portalLink.polyline];
		});
	} else if ([object isKindOfClass:[ControlField class]]) {
		ControlField *controlField = (ControlField *)object;
		[mapGuids removeObject:controlField.guid];
		dispatch_async(dispatch_get_main_queue(), ^{
			[_mapView removeOverlay:controlField.polygon];
		});
	} else if ([object isKindOfClass:[DeployedResonator class]]) {
		DeployedResonator *resonator = (DeployedResonator *)object;
		[mapGuids removeObject:[NSString stringWithFormat:@"%@-%d", resonator.portal.guid, resonator.slot]];
		dispatch_async(dispatch_get_main_queue(), ^{
			[_mapView removeOverlay:resonator.circle];
		});
	}
	
}

#pragma mark - NSManagedObjectContext Did Change

- (void)managedObjectContextObjectsDidChange:(NSNotification *)notification {
	NSArray *deletedObject = [notification.userInfo[NSInsertedObjectsKey] allObjects];
	for (NSManagedObject *object in deletedObject) {
		[self removeObjectFromMapView:object];
	}

	NSArray *insertedObject = [notification.userInfo[NSInsertedObjectsKey] allObjects];
	for (NSManagedObject *object in insertedObject) {
		[self insertObjectToMapView:object];
	}

	NSArray *updatedObject = [notification.userInfo[NSUpdatedObjectsKey] allObjects];
	for (NSManagedObject *object in updatedObject) {
		[self removeObjectFromMapView:object];
		[self insertObjectToMapView:object];
	}
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _xmOverlay.globs = [EnergyGlob MR_findAll];
        [_xmOverlayView setNeedsDisplayInMapRect:_mapView.visibleMapRect];
    });

}

#pragma mark - Update

- (void)updateCircle {

	if ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorized) {
		if (!locationAllowHUD) {
			_mapView.hidden = YES;
			rangeCircleView.hidden = YES;
			playerArrowImage.hidden = YES;
			locationAllowHUD = [[MBProgressHUD alloc] initWithView:self.view];
			locationAllowHUD.userInteractionEnabled = NO;
			locationAllowHUD.mode = MBProgressHUDModeCustomView;
			locationAllowHUD.customView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"warning.png"]];
			locationAllowHUD.labelText = @"Please allow location services";
			locationAllowHUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
			locationAllowHUD.removeFromSuperViewOnHide = YES;
			__weak __block typeof(locationAllowHUD) weakLocationAllowHUD = locationAllowHUD;
			locationAllowHUD.completionBlock = ^{
				weakLocationAllowHUD = nil;
			};
			[self.view addSubview:locationAllowHUD];
			[locationAllowHUD show:YES];
		}
	} else {
		if (locationAllowHUD) {
			[locationAllowHUD hide:YES];
			_mapView.hidden = NO;
			rangeCircleView.hidden = NO;
			playerArrowImage.hidden = NO;
		} else {
			CGFloat diameter = 0.;
			if (_mapView.bounds.size.width > 0) {
				diameter = 100/((_mapView.region.span.latitudeDelta * 111200) / _mapView.bounds.size.width);
			}
			rangeCircleView.frame = CGRectMake(0, 0, diameter, diameter);
			rangeCircleView.center = CGPointMake(_mapView.center.x, _mapView.center.y+10);
			rangeCircleView.layer.cornerRadius = diameter/2;
		}
	}

}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
	[_mapView setCenterCoordinate:newLocation.coordinate animated:!firstLocationUpdate];
	if (firstLocationUpdate) firstLocationUpdate = NO;
}

- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager {
	return NO;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
	CGAffineTransform transform = CGAffineTransformMakeRotation(newHeading.trueHeading*(M_PI/180));
	playerArrowImage.transform = transform;
	playerArrowImage.center = _mapView.center;
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];

	if (actionSheet.tag == 1 && buttonIndex == 0) {

		__block Item *item = currentItem;

		__block MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
		HUD.userInteractionEnabled = YES;
		HUD.mode = MBProgressHUDModeIndeterminate;
		HUD.dimBackground = YES;
		HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
		HUD.labelText = @"Picking up...";
		[[AppDelegate instance].window addSubview:HUD];
		[HUD show:YES];

		[[API sharedInstance] pickUpItemWithGuid:item.guid completionHandler:^(NSString *errorStr) {

			[HUD hide:YES];

			[_mapView removeAnnotation:item];
			item.latitude = 0;
			item.longitude = 0;
			item.dropped = NO;

			[[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:nil];

			if (errorStr) {

				HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
				HUD.userInteractionEnabled = YES;
				HUD.dimBackground = YES;
				HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
				HUD.mode = MBProgressHUDModeCustomView;
				HUD.customView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"warning.png"]];
				HUD.detailsLabelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
				HUD.detailsLabelText = errorStr;
				[[AppDelegate instance].window addSubview:HUD];
				[HUD show:YES];
				[HUD hide:YES afterDelay:3];

			} else {
				[[API sharedInstance] playSound:@"SFX_RESOURCE_PICK_UP"];
			}
			
		}];

	}
}

#pragma mark - MKMapViewDelegate

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {

	if (mapView.zoomLevel < 16) {
        [mapView setCenterCoordinate:_mapView.centerCoordinate zoomLevel:16 animated:NO];
		return;
    }

	NSDictionary *playerInfo = [[API sharedInstance] playerInfo];
	int ap = [playerInfo[@"ap"] intValue];
	int level = [API levelForAp:ap];
	int energy = [playerInfo[@"energy"] intValue];
	int maxEnergy = [API maxXmForLevel:level];
	int collecting = 0;

	if (energy < maxEnergy) {
		[[[API sharedInstance] energyToCollect] removeAllObjects];
		for (EnergyGlob *xm in [EnergyGlob MR_findAll]) {
			if ([xm distanceFromCoordinate:_mapView.centerCoordinate] <= 30) {
				[[[API sharedInstance] energyToCollect] addObject:xm];
				collecting += xm.amount;
			}
			if (collecting >= (maxEnergy-energy)) {
				break;
			}
		}
		//NSLog(@"Collecting %d (%d) XM", [[[API sharedInstance] energyToCollect] count], collecting);
	}

	CLLocation *mapLocation = [[CLLocation alloc] initWithLatitude:_mapView.centerCoordinate.latitude longitude:_mapView.centerCoordinate.longitude];
	CLLocationDistance meters = [mapLocation distanceFromLocation:lastLocation];
	if (meters == -1 || meters >= 10) {
		lastLocation = mapLocation;
		[self refresh];
	}

}

- (void)mapViewDidFinishLoadingMap:(MKMapView *)mapView {
    [EAGLContext setCurrentContext:nil];
}

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view {
	[_mapView deselectAnnotation:view.annotation animated:NO];
	if ([view.annotation isKindOfClass:[Portal class]]) {
		currentPortal = (Portal *)view.annotation;
		[self performSegueWithIdentifier:@"PortalDetailSegue" sender:self];
	} else if ([view.annotation isKindOfClass:[Item class]]) {
		if ([(Item *)(view.annotation) distanceFromCoordinate:_mapView.centerCoordinate] <= 30) {
			[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];
			
			currentItem = (Item *)view.annotation;
			UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:currentItem.title delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Acquire", nil];
			actionSheet.tag = 1;
			[actionSheet showFromTabBar:self.tabBarController.tabBar];
		}
	}
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation {
	
	if ([annotation isKindOfClass:[Portal class]]) {
		
		static NSString *AnnotationViewID = @"portalAnnotationView";
		
		MKAnnotationView *annotationView = /*(PortalAnnotationView *)*/[_mapView dequeueReusableAnnotationViewWithIdentifier:AnnotationViewID];
		if (annotationView == nil) {
			annotationView = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:AnnotationViewID];
			annotationView.canShowCallout = NO;
		}
		
		annotationView.annotation = annotation;
		
		Portal *portal = (Portal *)annotation;
		annotationView.image = [[API sharedInstance] iconForPortal:portal];
		annotationView.alpha = 0;

		return annotationView;
	
	} else if ([annotation isKindOfClass:[Item class]]) {
		
		static NSString *AnnotationViewID = @"itemAnnotationView";
		
		MKPinAnnotationView *annotationView = (MKPinAnnotationView *)[_mapView dequeueReusableAnnotationViewWithIdentifier:AnnotationViewID];
		if (annotationView == nil) {
			annotationView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:AnnotationViewID];
			annotationView.canShowCallout = NO;
			annotationView.pinColor = MKPinAnnotationColorPurple;
		}
		
		annotationView.annotation = annotation;
		
		return annotationView;
		
	}
	
	return nil;

}

- (MKOverlayView *)mapView:(MKMapView *)mapView viewForOverlay:(id<MKOverlay>)overlay {
	if ([overlay isKindOfClass:[Portal class]]) {
		PortalOverlayView *overlayView = [[PortalOverlayView alloc] initWithOverlay:overlay];
		return overlayView;
	} else if ([overlay isKindOfClass:[MKPolyline class]]) {
		MKPolyline *polyline = (MKPolyline *)overlay;
		MKPolylineView *polylineView = [[MKPolylineView alloc] initWithPolyline:polyline];
		polylineView.strokeColor = [API colorForFaction:polyline.portalLink.controllingTeam];
		polylineView.lineWidth = 1;
		return polylineView;
	} else if ([overlay isKindOfClass:[MKPolygon class]]) {
		MKPolygon *polygon = (MKPolygon *)overlay;
		MKPolygonView *polygonView = [[MKPolygonView alloc] initWithPolygon:polygon];
		polygonView.fillColor = [API colorForFaction:polygon.controlField.controllingTeam];
		polygonView.alpha = .1;
		return polygonView;
	} else if ([overlay isKindOfClass:[MKCircle class]]) {
		MKCircle *circle = (MKCircle *)overlay;
		if (circle.deployedResonator) {
			DeployedResonatorView *circleView = [[DeployedResonatorView alloc] initWithCircle:circle];
			circleView.fillColor = [API colorForLevel:circle.deployedResonator.level];
			return circleView;
        }
	} else if ([overlay isKindOfClass:[XMOverlay class]]) {
        XMOverlayView *xmOverlayView = [[XMOverlayView alloc] initWithOverlay:overlay];
        _xmOverlayView = xmOverlayView;
        return xmOverlayView;
    }
	return nil;
}

#pragma mark - Zoom Level

- (NSUInteger)zoomLevelForRegion:(MKCoordinateRegion)region {
    double centerPixelX = [MKMapView longitudeToPixelSpaceX: region.center.longitude];
    double topLeftPixelX = [MKMapView longitudeToPixelSpaceX: region.center.longitude - region.span.longitudeDelta / 2];
    double scaledMapWidth = (centerPixelX - topLeftPixelX) * 2;
    CGSize mapSizeInPixels = _mapView.bounds.size;
    double zoomScale = scaledMapWidth / mapSizeInPixels.width;
    double zoomExponent = log(zoomScale) / log(2);
    double zoomLevel = 20 - zoomExponent;
    return zoomLevel;
}

#pragma mark - Gestures

- (void)handlePinch:(UIPinchGestureRecognizer*)recognizer {
    static MKCoordinateRegion originalRegion;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        originalRegion = _mapView.region;
    }

    double latdelta = originalRegion.span.latitudeDelta / recognizer.scale;
    double londelta = originalRegion.span.longitudeDelta / recognizer.scale;
    MKCoordinateSpan span = MKCoordinateSpanMake(latdelta, londelta);
	MKCoordinateRegion region = MKCoordinateRegionMake(originalRegion.center, span);

	if ([self zoomLevelForRegion:region] >= 16) {
		[_mapView setRegion:region animated:NO];
	}
    
}

- (void)mapTapped:(UITapGestureRecognizer *)recognizer {

	if (_mapView.scrollEnabled) {
		[locationManager startUpdatingLocation];
		[_mapView setScrollEnabled:NO];
	} else {
		[locationManager stopUpdatingLocation];
		[_mapView setScrollEnabled:YES];
	}

//	MKMapView *mapView = (MKMapView *)recognizer.view;
//	id<MKOverlay> tappedOverlay = nil;
//	for (id<MKOverlay> overlay in mapView.overlays) {
//		if (![overlay isKindOfClass:[Portal class]]) { continue; }
//		MKOverlayView *view = [mapView viewForOverlay:overlay];
//		if (view) {
//			// Get view frame rect in the mapView's coordinate system
//			CGRect viewFrameInMapView = [view.superview convertRect:view.frame toView:mapView];
//			// Get touch point in the mapView's coordinate system
//			CGPoint point = [recognizer locationInView:mapView];
//			// Check if the touch is within the view bounds
//			if (CGRectContainsPoint(viewFrameInMapView, point)) {
//				tappedOverlay = overlay;
//				break;
//			}
//		}
//	}
//
////	NSLog(@"Tapped overlay: %@", tappedOverlay);
////	NSLog(@"Tapped view: %@", [mapView viewForOverlay:tappedOverlay]);
//
//	if ([tappedOverlay isKindOfClass:[Portal class]]) {
//		currentPortal = (Portal *)tappedOverlay;
//		[self performSegueWithIdentifier:@"PortalDetailSegue" sender:self];
//	}
	
}

- (void)mapLongPress:(UILongPressGestureRecognizer *)recognizer {
	if (recognizer.state == UIGestureRecognizerStateBegan) {

		[self becomeFirstResponder];
        CGPoint location = [recognizer locationInView:recognizer.view];
        UIMenuController *menuController = [UIMenuController sharedMenuController];
        UIMenuItem *resetMenuItem = [[UIMenuItem alloc] initWithTitle:@"Fire XMP" action:@selector(fireXMP)];
        [menuController setMenuItems:[NSArray arrayWithObject:resetMenuItem]];
        [menuController setTargetRect:CGRectMake(location.x, location.y, 0.0f, 0.0f) inView:recognizer.view];
        [menuController setMenuVisible:YES animated:YES];

	}
}

#pragma mark - Actions

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (BOOL)canPerformAction:(SEL)selector withSender:(id) sender {
    if (selector == @selector(fireXMP)) {
        return YES;
    }
    return NO;
}

#pragma mark - Firing XMP

- (void)fireXMP {

//	int ap = [[API sharedInstance].playerInfo[@"ap"] intValue];
//	int level = [API levelForAp:ap];
//	[self fireXMPOfLevel:level];
	
	[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];
		
	MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
	HUD.userInteractionEnabled = YES;
	HUD.mode = MBProgressHUDModeCustomView;
	HUD.dimBackground = YES;
	HUD.showCloseButton = YES;
	
	_levelChooser = [LevelChooserViewController levelChooserWithTitle:@"Choose XMP burster level to fire" completionHandler:^(int level) {
		[HUD hide:YES];
		[self fireXMPOfLevel:level];
		_levelChooser = nil;
	}];
	HUD.customView = _levelChooser.view;
	
	[[AppDelegate instance].window addSubview:HUD];
	[HUD show:YES];
	
}

- (void)fireXMPOfLevel:(int)level {
	
	XMP *xmpItem = [XMP MR_findFirstWithPredicate:[NSPredicate predicateWithFormat:@"dropped = NO && level = %d", level]];

//	NSLog(@"Firing: %@", xmpItem);

	[[SoundManager sharedManager] playSound:@"Sound/sfx_emp_power_up.aif"];
	
	if (!xmpItem) {
		MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
		HUD.userInteractionEnabled = YES;
		HUD.dimBackground = YES;
		HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
		HUD.mode = MBProgressHUDModeCustomView;
		HUD.customView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"warning.png"]];
		HUD.detailsLabelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
		HUD.detailsLabelText = @"No XMP remaining!";
		[[AppDelegate instance].window addSubview:HUD];
		[HUD show:YES];
		[HUD hide:YES afterDelay:3];
		return;
	}
	
	MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
	HUD.userInteractionEnabled = YES;
	HUD.dimBackground = YES;
	HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
	HUD.labelText = [NSString stringWithFormat:@"Firing XMP of level: %d", level];
	[[AppDelegate instance].window addSubview:HUD];
	[HUD show:YES];
	
	[[API sharedInstance] fireXMP:xmpItem completionHandler:^(NSString *errorStr, NSDictionary *damages) {
		
		[HUD hide:YES];
		
		MBProgressHUD *HUD = [[MBProgressHUD alloc] initWithView:[AppDelegate instance].window];
		HUD.userInteractionEnabled = YES;
		HUD.dimBackground = YES;
		HUD.labelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
		
		if (damages) {
			
//			HUD.mode = MBProgressHUDModeText;
//			HUD.labelText = @"Damages";
//			HUD.detailsLabelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:10];
			
			UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 240, 320)];
			textView.editable = NO;
			textView.backgroundColor = [UIColor clearColor];
			textView.opaque = NO;
			textView.textColor = [UIColor whiteColor];
			
			HUD.mode = MBProgressHUDModeCustomView;
			HUD.customView = textView;
			HUD.showCloseButton = YES;
			
			NSMutableString *damagesStr = [NSMutableString string];
			
			[damages enumerateKeysAndObjectsUsingBlock:^(NSString *portalGUID, NSArray *damagesArray, BOOL *stop) {

				Portal *portal = [Portal MR_findFirstByAttribute:@"guid" withValue:portalGUID];
				[damagesStr appendFormat:@"%@:\n", portal.subtitle];
				
				for (NSDictionary *damage in damagesArray) {
					int damageAmount = [damage[@"damageAmount"] intValue];
					int slot = [damage[@"targetSlot"] intValue];
					BOOL critical = [damage[@"criticalHit"] boolValue];
					BOOL destroyed = [damage[@"targetDestroyed"] boolValue];
					
					if (destroyed) {
						[[SoundManager sharedManager] playSound:@"Sound/sfx_explode_resonator.aif"];
					}
					
					DeployedResonator *resonator = [DeployedResonator MR_findFirstWithPredicate:[NSPredicate predicateWithFormat:@"portal = %@ && slot = %d", portal, slot]];
					int level = resonator.level;
					int maxEnergy = [API maxEnergyForResonatorLevel:level];
					
					[damagesStr appendFormat:@"  • %d: -%d/%d %@%@\n", slot, damageAmount, maxEnergy, (critical ? @" CRITICAL" : @""), (destroyed ? @" DESTROYED" : @"")];

					[[NSNotificationCenter defaultCenter] postNotificationName:@"ResonatorDamage" object:resonator userInfo:@{
					 @"damageAmount": @(damageAmount),
					 @"critical": @(critical),
					 @"destroyed": @(destroyed)
					}];
					
				}
				
				[damagesStr appendFormat:@"\n\n"];
				
			}];
			

			textView.text = damagesStr;
			
			//[[AppDelegate instance].window addSubview:HUD];
			//[HUD show:YES];

		} else {
			
			HUD.mode = MBProgressHUDModeCustomView;
			HUD.customView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"warning.png"]];
			HUD.detailsLabelFont = [UIFont fontWithName:[[[UILabel appearance] font] fontName] size:16];
			
			if (errorStr) {
				HUD.detailsLabelText = errorStr;
			} else {
				HUD.detailsLabelText = @"Unknown Error";
			}
			
			[[AppDelegate instance].window addSubview:HUD];
			[HUD show:YES];
			[HUD hide:YES afterDelay:3];
			
		}

	}];
	
}

#pragma mark - Storyboard

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
	if ([segue.identifier isEqualToString:@"PortalDetailSegue"]) {
		[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];

		portalDetailSegue = YES;
		
		PortalDetailViewController *vc = segue.destinationViewController;
		vc.portal = currentPortal;
		currentPortal = nil;
	} else if ([segue.identifier isEqualToString:@"FactionChooseSegue"]) {
		portalDetailSegue = NO;

		MissionViewController *vc = segue.destinationViewController;
		vc.factionChoose = YES;
	}
}

@end
