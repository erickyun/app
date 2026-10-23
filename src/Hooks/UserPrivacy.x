//
//  UserPrivacy.x
//  NeoFreeBird
//
//  Display-only privacy controls. Keep the underlying user/status models intact
//  so links, IDs, tap actions and account operations continue working.
//

#import "HookHelpers.h"

// These accessors are present in the app's ObjC UI classes (X 12.3).
@interface TTAStatusAuthorView (BHTUserPrivacyLabels)
@property (nonatomic, readonly) UILabel* fullNameLabel;
@property (nonatomic, readonly) UILabel* usernameLabel;
@end

@interface T1UserView : UIView
@property (nonatomic, readonly) UILabel* fullNameLabel;
@property (nonatomic, readonly) UILabel* userNameLabel;
@end

static char kBHTPrivacyOriginalHidden;

// We remember each view's original hidden state so switching a preference
// back off doesn't unhide controls that X had hidden itself.
static void BHTSetPrivacyHidden(UIView* view, BOOL hide) {
    if (!view) return;

    NSNumber* original = objc_getAssociatedObject(view, &kBHTPrivacyOriginalHidden);
    if (hide) {
        if (!original) {
            objc_setAssociatedObject(view, &kBHTPrivacyOriginalHidden,
                                     @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!view.hidden) view.hidden = YES;
    } else if (original) {
        objc_setAssociatedObject(view, &kBHTPrivacyOriginalHidden, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (view.hidden != original.boolValue) view.hidden = original.boolValue;
    }
}

static BOOL BHTIsUserAvatarView(UIView* view) {
    NSString* name = NSStringFromClass([view class]);
    // Both UIKit and Swift avatar renderers are used. Match avatar-specific
    // view classes only, rather than UIImageView or every user-supplied image.
    return [name hasSuffix:@"AvatarImageView"] ||
           [name hasSuffix:@"AvatarHeaderView"] ||
           [name hasSuffix:@"DrawerAvatarImageView"] ||
           [name hasSuffix:@"UserFacepileView"];
}

void BHTApplyPrivacyToView(UIView* view) {
    if (!view) return;

    if (BHTIsUserAvatarView(view)) {
        BHTSetPrivacyHidden(view, [BHTSettings boolForKey:@"hide_user_avatars"]);
    }

    Class statusAuthorClass = objc_getClass("TTAStatusAuthorView");
    if (statusAuthorClass && [view isKindOfClass:statusAuthorClass]) {
        TTAStatusAuthorView* author = (TTAStatusAuthorView*)view;
        BHTSetPrivacyHidden(author.fullNameLabel, [BHTSettings boolForKey:@"hide_user_names"]);
        BHTSetPrivacyHidden(author.usernameLabel, [BHTSettings boolForKey:@"hide_user_usernames"]);
    }

    Class userViewClass = objc_getClass("T1UserView");
    if (userViewClass && [view isKindOfClass:userViewClass]) {
        T1UserView* user = (T1UserView*)view;
        BHTSetPrivacyHidden(user.fullNameLabel, [BHTSettings boolForKey:@"hide_user_names"]);
        BHTSetPrivacyHidden(user.userNameLabel, [BHTSettings boolForKey:@"hide_user_usernames"]);
    }
}

static void BHTVisitPrivacySubviews(UIView* view) {
    if (!view) return;
    BHTApplyPrivacyToView(view);
    // Do not skip hidden subtrees: a previously hidden avatar must be restored.
    for (UIView* child in view.subviews) {
        BHTVisitPrivacySubviews(child);
    }
}

void applyUserPrivacySettings(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            applyUserPrivacySettings();
        });
        return;
    }

    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        BHTVisitPrivacySubviews(window);
        // Rebuild layout state (including profile-header name/subtitle labels).
        [window setNeedsLayout];
    }
}

// These values are exclusively for the author row's layout. The original
// status model still contains the real name and handle for navigation, sharing,
// accessibility of other UI elements and network requests.
%hook TTAStatusAuthorViewLayoutState

- (NSString*)fullName {
    return [BHTSettings boolForKey:@"hide_user_names"] ? @"" : %orig;
}

- (NSString*)truncatedFullName {
    return [BHTSettings boolForKey:@"hide_user_names"] ? @"" : %orig;
}

- (NSString*)displayUsername {
    return [BHTSettings boolForKey:@"hide_user_usernames"] ? @"" : %orig;
}

- (NSString*)truncatedUsername {
    return [BHTSettings boolForKey:@"hide_user_usernames"] ? @"" : %orig;
}

%end

// Covers author rows in timelines, conversations, quote tweets and immersive
// media, without touching tweet text, timestamps or engagement counters.
%hook TTAStatusAuthorView

- (void)_updateContent {
    %orig;
    BHTApplyPrivacyToView((UIView*)self);
}

- (void)layoutSubviews {
    %orig;
    BHTApplyPrivacyToView((UIView*)self);
}

%end

// User-list/search/followers rows have a different pair of named labels.
%hook T1UserView

- (void)_update {
    %orig;
    BHTApplyPrivacyToView((UIView*)self);
}

- (void)layoutSubviews {
    %orig;
    BHTApplyPrivacyToView((UIView*)self);
}

%end

// Profile summaries build their full-name and @handle labels on demand,
// rather than exposing permanent label properties.
%hook T1ProfileSummaryView

- (void)_t1_updatePropertiesForFullNameLabel:(id)nameLabel
                               subtitleLabel:(id)subtitleLabel
                                  atPosition:(unsigned long long)position {
    %orig;
    if ([nameLabel isKindOfClass:[UIView class]]) {
        BHTSetPrivacyHidden(nameLabel, [BHTSettings boolForKey:@"hide_user_names"]);
    }
    if ([subtitleLabel isKindOfClass:[UIView class]]) {
        BHTSetPrivacyHidden(subtitleLabel, [BHTSettings boolForKey:@"hide_user_usernames"]);
    }
}

%end

// The classic avatar family powers profile photos, account rows and feeds.
%hook TFNAvatarImageView

- (void)layoutSubviews {
    %orig;
    BHTApplyPrivacyToView((UIView*)self);
}

%end

%hook TFNAvatarHeaderView

- (void)layoutSubviews {
    %orig;
    BHTApplyPrivacyToView((UIView*)self);
}

%end

// Direct-message avatars use an independent image view.
%hook T1AvatarImageView

- (void)layoutSubviews {
    %orig;
    BHTApplyPrivacyToView((UIView*)self);
}

%end
