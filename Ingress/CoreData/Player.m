//
//  Player.m
//  Ingress
//
//  Created by Alex Studnička on 23.05.13.
//  Copyright (c) 2013 A&A Code. All rights reserved.
//

#import "Player.h"


@implementation Player

@dynamic ap;
@dynamic energy;
@dynamic shouldSendEmail;
@dynamic maySendPromoEmail;
@dynamic allowNicknameEdit;
@dynamic allowFactionChoice;
@dynamic shouldPushNotifyForAtPlayer;
@dynamic shouldPushNotifyForPortalAttacks;

- (int)level {
	return [API levelForAp:self.ap];
}

- (int)maxEnergy {
	return [API maxXmForLevel:self.level];
}

- (int)nextLevelAP {
	return [API maxApForLevel:self.level];
}

@end
