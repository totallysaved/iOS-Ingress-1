//
//  MediaWebViewViewController.m
//  Ingress
//
//  Created by Alex Studnička on 10.05.13.
//  Copyright (c) 2013 A&A Code. All rights reserved.
//

#import "MediaWebViewViewController.h"

@implementation MediaWebViewViewController

@synthesize media = _media;

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

	self.navigationItem.title = self.media.name;

	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:self.media.url]];
	_webView.scalesPageToFit = YES;
	[_webView loadRequest:request];
}

#pragma mark - IBActions

- (IBAction)close {
	[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)action {
	[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];

	UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Open in Safari", nil];
	actionSheet.tag = 1;
	[actionSheet showInView:self.view];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	[[SoundManager sharedManager] playSound:@"Sound/sfx_ui_success.aif"];
	if (actionSheet.tag == 1 && buttonIndex == 0) {
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:self.media.url]];
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

@end
