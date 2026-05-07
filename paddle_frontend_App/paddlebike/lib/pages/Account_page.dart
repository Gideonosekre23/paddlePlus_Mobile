import 'package:flutter/material.dart';

import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddlebike/Apiendpoints/apiservices/auth_api_service.dart';
import 'package:paddlebike/Apiendpoints/apiservices/wallet_api_service.dart';
import 'package:paddlebike/Apiendpoints/models/auth_models.dart';
import 'package:paddlebike/pages/Settings_page.dart';
import 'package:paddlebike/pages/login_page.dart';
import 'package:paddlebike/pages/Accountdetail_page.dart';
import 'package:paddlebike/pages/stripe_page.dart';
import 'package:paddlebike/Apiendpoints/apiservices/Image_utils.dart';

class Account_page extends StatefulWidget {
  final User? user;

  const Account_page({super.key, this.user});

  @override
  State<Account_page> createState() => _Account_pageState();
}

class _Account_pageState extends State<Account_page> {
  bool _isLoggingOut = false;
  bool _isConnectingStripe = false;
  bool _stripeConnected = false;
  bool _isWithdrawing = false;
  double _pendingBalance = 0.0;

  final UserSessionManager _sessionManager = UserSessionManager();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = _sessionManager.currentUser ?? widget.user;
    _pendingBalance = _currentUser?.pending_balance ?? 0.0;
    _sessionManager.addListener(_onSessionChanged);
    _checkStripeStatus();
    _refreshWalletBalance();
  }

  Future<void> _checkStripeStatus() async {
    try {
      final resp = await AuthApiService.getStripeConnectStatus();
      if (mounted && resp.success) {
        setState(() => _stripeConnected = resp.data?['connected'] == true);
      }
    } catch (_) {}
  }

  Future<void> _refreshWalletBalance() async {
    try {
      final resp = await WalletApiService.getWalletBalance();
      if (mounted && resp.success && resp.data != null) {
        setState(() {
          _pendingBalance = (resp.data!['pending_balance'] as num?)?.toDouble() ?? _pendingBalance;
          _stripeConnected = resp.data!['stripe_ready'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _requestWithdrawal() async {
    if (_isWithdrawing) return;

    if (!_stripeConnected) {
      await _openStripeConnect();
      return;
    }

    if (_pendingBalance < 1.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum withdrawal is \$1.00'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Show fee confirmation dialog
    final fee = _pendingBalance * 0.015;
    final net = _pendingBalance - fee;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Withdrawal'),
        content: Text(
          'Balance: \$${_pendingBalance.toStringAsFixed(2)}\n'
          'Fee (1.5%): -\$${fee.toStringAsFixed(2)}\n'
          'You\'ll receive: \$${net.toStringAsFixed(2)}\n\n'
          'Arrives in minutes via your connected account.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWithdrawing = true);
    try {
      final resp = await WalletApiService.requestWithdrawal();
      if (!mounted) return;
      if (resp.success) {
        final method = resp.data?['method'] as String? ?? 'instant';
        final arrival = method == 'instant' ? 'Arrives in minutes!' : 'Arrives in 1–2 business days.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payout sent! $arrival'), backgroundColor: Colors.green),
        );
        setState(() => _pendingBalance = 0.0);
        await _refreshWalletBalance();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.error ?? 'Withdrawal failed'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  @override
  void dispose() {
    // ✅ Remove listener
    _sessionManager.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted && _sessionManager.currentUser != null) {
      setState(() {
        _currentUser = _sessionManager.currentUser;
        _pendingBalance = _currentUser?.pending_balance ?? _pendingBalance;
      });
    }
  }

  Future<void> _openStripeConnect() async {
    if (_isConnectingStripe) return;
    setState(() => _isConnectingStripe = true);

    try {
      final statusResp = await AuthApiService.getStripeConnectStatus();
      if (!mounted) return;

      if (statusResp.success && statusResp.data?['connected'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payout account already connected and ready.'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      final connectResp = await AuthApiService.connectStripeAccount();
      if (!mounted) return;

      if (connectResp.success && connectResp.data?['onboarding_url'] != null) {
        final url = connectResp.data!['onboarding_url'] as String;
        if (!url.startsWith('https://')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid payout setup URL received. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StripeVerificationWebViewPage(initialUrl: url),
          ),
        );
        if (mounted) {
          await _checkStripeStatus();
          await _refreshWalletBalance();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(connectResp.error ?? 'Failed to start payout setup'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnectingStripe = false);
    }
  }

  Future<void> _showPayoutHistory() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PayoutHistorySheet(),
    );
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() {
      _isLoggingOut = true;
    });

    try {
      await _sessionManager.logout(notifyApi: true);

      print("✅ UserSessionManager logout completed");

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const login_page()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      print("❌ Logout error: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Use current user instead of widget.user
    final String username = _currentUser?.username ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          username,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ImageUtils.buildAvatar(
              profilePicture: _currentUser?.profilePicture,
              radius: 20,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    ImageUtils.buildAvatar(
                      profilePicture:
                          _currentUser?.profilePicture, // ✅ Use current user
                      radius: 50,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentUser?.email ?? 'No email', // ✅ Use current user
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.settings,
                  color: Color.fromARGB(255, 118, 172, 198),
                ),
                title: const Text(
                  "Settings",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const Settings_Page(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.person,
                  color: Color.fromARGB(255, 118, 172, 198),
                ),
                title: const Text(
                  "Account Details",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: () async {
                  // ✅ UPDATED: Navigate and refresh on return
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Accountdetail_page(
                        user: _currentUser!, // Pass current user
                      ),
                    ),
                  );

                  // ✅ Force refresh when returning
                  if (result == true && mounted) {
                    setState(() {
                      _currentUser =
                          _sessionManager.currentUser ?? _currentUser;
                    });
                    print(
                      '🔄 Returned from account details, refreshing user data',
                    );
                  }
                },
              ),
              // Wallet balance card
              Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet, color: Color.fromARGB(255, 118, 172, 198)),
                          const SizedBox(width: 8),
                          const Text('Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: _refreshWalletBalance,
                            tooltip: 'Refresh balance',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '\$${_pendingBalance.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const Text('Available to withdraw', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_isWithdrawing || _pendingBalance <= 0) ? null : _requestWithdrawal,
                          icon: _isWithdrawing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send),
                          label: Text(_isWithdrawing ? 'Processing…' : 'Withdraw Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showPayoutHistory,
                          child: const Text('View History', style: TextStyle(color: Color.fromARGB(255, 118, 172, 198))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: _isConnectingStripe
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.account_balance,
                        color: _stripeConnected ? Colors.green : const Color.fromARGB(255, 118, 172, 198),
                      ),
                title: const Text(
                  "Payout Account",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(_stripeConnected ? "Connected — ready to receive payouts" : "Set up bank account to withdraw earnings"),
                trailing: const Icon(Icons.chevron_right),
                onTap: _isConnectingStripe ? null : _openStripeConnect,
              ),
              ListTile(
                leading: const Icon(
                  Icons.help,
                  color: Color.fromARGB(255, 118, 172, 198),
                ),
                title: const Text(
                  "Help & Support",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Help & Support'),
                      content: const Text(
                        'Need help? Contact us at:\n\nsupport@paddleplus.app\n\nWe typically respond within 24 hours.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                      ],
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: _isLoggingOut
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                        ),
                      )
                    : const Icon(Icons.logout, color: Colors.red),
                title: Text(
                  _isLoggingOut ? "Logging out..." : "Logout",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                onTap: _isLoggingOut ? null : _logout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayoutHistorySheet extends StatefulWidget {
  @override
  State<_PayoutHistorySheet> createState() => _PayoutHistorySheetState();
}

class _PayoutHistorySheetState extends State<_PayoutHistorySheet> {
  bool _loading = true;
  String? _error;
  List<dynamic> _payouts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await WalletApiService.getPayoutHistory();
      if (!mounted) return;
      if (resp.success && resp.data != null) {
        setState(() {
          _payouts = (resp.data!['payouts'] as List?) ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = resp.error ?? 'Failed to load history';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Payout History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : _payouts.isEmpty
                        ? const Center(child: Text('No payouts yet', style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            controller: controller,
                            itemCount: _payouts.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = _payouts[i] as Map<String, dynamic>;
                              final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
                              final status = p['status'] as String? ?? '';
                              final method = p['method'] as String? ?? '';
                              final dateStr = p['created_at'] as String? ?? '';
                              final date = DateTime.tryParse(dateStr);
                              final dateLabel = date != null
                                  ? '${date.day}/${date.month}/${date.year}'
                                  : dateStr;
                              return ListTile(
                                leading: Icon(
                                  status == 'paid' ? Icons.check_circle : Icons.schedule,
                                  color: status == 'paid' ? Colors.green : Colors.orange,
                                ),
                                title: Text('\$${amount.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('$method · $dateLabel',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: status == 'paid' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(status,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: status == 'paid' ? Colors.green : Colors.orange,
                                          fontWeight: FontWeight.w500)),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
