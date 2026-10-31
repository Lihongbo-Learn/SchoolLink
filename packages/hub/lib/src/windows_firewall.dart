import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// Ensures that the Windows firewall allows the LAN ports used by SchoolLink.
///
/// Windows requires elevation to modify firewall rules. The Hub itself stays
/// unelevated: we first run a read-only check, then ask Windows for one UAC
/// prompt to install the rules. A declined prompt never prevents the Hub from
/// starting; the school can still run tools/enable-firewall.ps1 manually.
Future<void> ensureWindowsFirewall({Logger? logger}) async {
  if (!Platform.isWindows) return;
  final log = logger ?? Logger('school_link_hub.firewall');
  try {
    final state = await _runPowerShell(_checkScript);
    if (state.trim().toLowerCase() == 'ok') {
      log.fine('Windows firewall already allows SchoolLink ports.');
      return;
    }
    log.info('Windows firewall is missing SchoolLink rules; requesting elevation.');
    await _elevate(_fixScript());
  } catch (error) {
    log.warning('Automatic firewall provisioning failed: $error');
  }
}

const String _checkScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
$allow = Get-NetFirewallRule -DisplayName 'SchoolLink Hub HTTP/WS 8421' -ErrorAction SilentlyContinue |
  Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' }
$block = Get-NetFirewallRule -Direction Inbound -Action Block -ErrorAction SilentlyContinue |
  Where-Object {
    $_.DisplayName -match 'schoollink' -or
    ((Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $_).Program -match 'SchoolLink')
  }
if ($allow -and -not $block) { 'ok' } else { 'fix' }
''';

String _fixScript() {
  final program = Platform.resolvedExecutable.replaceAll("'", "''");
  return r'''
$ErrorActionPreference = 'SilentlyContinue'
$blockRules = Get-NetFirewallRule -Direction Inbound -Action Block -ErrorAction SilentlyContinue
foreach ($rule in $blockRules) {
  $app = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
  if (($rule.DisplayName -match 'schoollink') -or ($app.Program -match 'SchoolLink')) {
    Remove-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
  }
}
Get-NetFirewallRule -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -like 'SchoolLink *' -or $_.Group -eq 'SchoolLink' } |
  Remove-NetFirewallRule -ErrorAction SilentlyContinue
$ports = @(
  @{ Name = 'SchoolLink Hub HTTP/WS 8421'; Protocol = 'TCP'; Port = '8421' },
  @{ Name = 'SchoolLink Hub Discovery 8421'; Protocol = 'UDP'; Port = '8421' },
  @{ Name = 'SchoolLink Peer 8422'; Protocol = 'TCP'; Port = '8422' },
  @{ Name = 'SchoolLink Peer Discovery 8424'; Protocol = 'UDP'; Port = '8424' }
)
foreach ($rule in $ports) {
  New-NetFirewallRule -DisplayName $rule.Name -Group 'SchoolLink' -Direction Inbound -Action Allow -Protocol $rule.Protocol -LocalPort $rule.Port -RemoteAddress LocalSubnet -Profile Public,Private -Enabled True | Out-Null
}
$program = '__PROGRAM__'
if (Test-Path $program) {
  New-NetFirewallRule -DisplayName 'SchoolLink Hub Program' -Group 'SchoolLink' -Direction Inbound -Action Allow -Program $program -RemoteAddress LocalSubnet -Profile Public,Private -Enabled True | Out-Null
}
'''
      .replaceFirst('__PROGRAM__', program);
}

Future<String> _runPowerShell(String script) async {
  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      _encodePowerShell(script),
    ],
  ).timeout(const Duration(seconds: 20));
  if (result.exitCode != 0) return 'fix';
  return result.stdout.toString();
}

Future<void> _elevate(String script) async {
  final encoded = _encodePowerShell(script);
  final command =
      "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden "
      "-ArgumentList '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded'";
  await Process.start(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command,
    ],
    mode: ProcessStartMode.detached,
  );
}

String _encodePowerShell(String script) {
  final bytes = <int>[];
  for (final unit in script.codeUnits) {
    bytes.add(unit & 0xff);
    bytes.add((unit >> 8) & 0xff);
  }
  return base64Encode(bytes);
}
