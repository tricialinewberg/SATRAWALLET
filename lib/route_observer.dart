import 'package:flutter/material.dart';

/// Shared observer so screens can react to being covered/uncovered by
/// another route — e.g. [WalletHomeScreen] pausing its ambient NFC
/// listener while another screen (in particular [NfcTransferScreen], which
/// runs its own NFC session) is on top, so only one NFC session is ever
/// active at a time.
final RouteObserver<PageRoute<void>> satraRouteObserver = RouteObserver<PageRoute<void>>();
