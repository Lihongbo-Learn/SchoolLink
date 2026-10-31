String appProfile = '';

String get appProfileSuffix => appProfile.isEmpty ? '' : '_$appProfile';

String get appProfileLabel => appProfile.isEmpty ? '默认' : appProfile;
