//
//  ProfilesSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/ProfilesSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"

extern void applySquareAvatarsSetting(void);
extern void applyUserPrivacySettings(void);

@implementation ProfilesSettingsViewController

- (NSString*)pageKey {
    return @"profiles";
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"square_avatars"]) {
        applySquareAvatarsSetting();
    } else if ([key isEqualToString:@"hide_user_usernames"] ||
               [key isEqualToString:@"hide_user_names"] ||
               [key isEqualToString:@"hide_user_avatars"]) {
        applyUserPrivacySettings();
    }
}

@end
