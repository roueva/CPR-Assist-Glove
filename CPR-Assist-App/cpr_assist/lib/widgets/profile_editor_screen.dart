import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../widgets/app_theme.dart';

class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen({super.key});

  @override
  ConsumerState<ProfileEditorScreen> createState() =>
      _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  late TextEditingController _nameController;
  bool _isSaving = false;
  bool _hasChanges = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final username = ref.read(authStateProvider).username ?? '';
    _nameController = TextEditingController(text: username);
    _nameController.addListener(_onChanged);
  }

  void _onChanged() {
    final original = ref.read(authStateProvider).username ?? '';
    setState(() {
      _hasChanges = _nameController.text.trim() != original;
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_onChanged);
    _nameController.dispose();
    super.dispose();
  }

  String get _initials {
    final s = _nameController.text.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _save() async {
    final newName = _nameController.text.trim();
    if (newName.length < 3) {
      setState(() => _errorMessage = 'Name must be at least 3 characters.');
      return;
    }

    setState(() { _isSaving = true; _errorMessage = null; });

    try {
      final networkService = ref.read(networkServiceProvider);

      // Calls PUT /auth/profile  — add this route in Node (see backend_additions.js)
      await networkService.put(
        '/auth/profile',
        {'username': newName},
        requiresAuth: true,
      );

      // Update local state so avatar initials refresh immediately everywhere
      await ref.read(authStateProvider.notifier).updateUsername(newName);

      if (mounted) {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('Profile updated'),
          ]),
          backgroundColor: kSuccess,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ));
      }
    } on Exception catch (e) {
      setState(() {
        _isSaving = false;
        final msg = e.toString().replaceFirst('Exception: ', '');
        _errorMessage = msg.contains('409')
            ? 'That username is already taken.'
            : 'Could not save. Check your connection.';
      });
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(children: [
                  Text('Discard changes?', style: kHeading(size: 16)),
                  const SizedBox(height: 8),
                  Text('Your unsaved changes will be lost.',
                      style: kBody(size: 13), textAlign: TextAlign.center),
                ]),
              ),
              const Divider(height: 1, color: kDivider),
              IntrinsicHeight(
                child: Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Keep editing',
                          style: kBody(size: 14, color: kPrimary)
                              .copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: kDivider),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Discard',
                          style: kBody(size: 14, color: kEmergency)
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: kBgGrey,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: kTextDark,
          elevation: 0,
          toolbarHeight: 52,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: kPrimary),
            onPressed: () async {
              if (await _onWillPop()) Navigator.of(context).pop();
            },
          ),
          title: Text('Edit Profile', style: kHeading(size: 18)),
          actions: [
            if (_hasChanges)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text('Save',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _isSaving ? kTextLight : kPrimary,
                      )),
                ),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: kDivider),
          ),
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Column(children: [
                  Stack(children: [
                    Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kPrimaryLight,
                        border: Border.all(color: kPrimaryMid, width: 2.5),
                      ),
                      child: Center(
                        child: Text(_initials,
                            style: const TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 28)),
                      ),
                    ),
                    Positioned(
                      bottom: 2, right: 2,
                      child: GestureDetector(
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Photo upload coming soon')),
                        ),
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: kPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_outlined,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('Tap camera to change photo',
                      style: kLabel(size: 11, color: kTextLight)),
                ]),
              ),
              const SizedBox(height: 28),
              Text('DISPLAY NAME', style: kLabel(size: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _hasChanges ? _save() : null,
                decoration: InputDecoration(
                  hintText: 'Your name',
                  hintStyle: const TextStyle(color: kTextLight),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kDivider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kDivider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                      const BorderSide(color: kPrimary, width: 1.5)),
                  errorText: _errorMessage,
                  errorStyle:
                  const TextStyle(color: kEmergency, fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This name appears on the leaderboard and in session reports.',
                style: kLabel(size: 11, color: kTextLight),
              ),
              const SizedBox(height: 32),
              AnimatedOpacity(
                opacity: _hasChanges ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_hasChanges && !_isSaving) ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kPrimary,
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ))
                        : const Text('Save Changes',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}