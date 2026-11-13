"""Static signing regression: default app tokens must remain private to each target."""
import pathlib
import plistlib

root = pathlib.Path(__file__).resolve().parents[2] / 'ios'
private_group = '$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)'
shared_group = '$(AppIdentifierPrefix)$(SURE_WIDGET_KEYCHAIN_GROUP)'
for target, entitlement in [('Runner', 'Runner.entitlements'), ('SureWidget', 'SureWidget.entitlements')]:
    with (root / target / entitlement).open('rb') as f:
        groups = plistlib.load(f)['keychain-access-groups']
    assert groups == [private_group, shared_group], f'{target}: preserve private default before explicit shared group'
    with (root / target / 'Info.plist').open('rb') as f:
        info = plistlib.load(f)
    assert info['SureWidgetKeychainGroup'] == shared_group
    assert info['SureAppGroup'] == '$(SURE_APP_GROUP)'
print('Widget credential entitlement checks passed')
