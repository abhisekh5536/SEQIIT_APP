import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/db_models.dart';
import '../../models/notice_models.dart';
import '../../services/app_session.dart';
import '../../services/notices_service.dart';
import '../../theme/app_theme.dart';

class CreateEditNoticeScreen extends StatefulWidget {
  final NoticeRecord? noticeToEdit;

  const CreateEditNoticeScreen({super.key, this.noticeToEdit});

  @override
  State<CreateEditNoticeScreen> createState() => _CreateEditNoticeScreenState();
}

class _CreateEditNoticeScreenState extends State<CreateEditNoticeScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _venueController;

  late NoticeCategory _category;
  late NoticeTargetType _targetType;
  String? _selectedBlockId;
  List<BlockInfo> _availableBlocks = [];

  bool _isEvent = false;
  DateTime? _eventDate;
  TimeOfDay? _eventStartTime;
  TimeOfDay? _eventEndTime;

  bool _isPinned = false;
  bool _requiresAck = false;

  bool _scheduleForLater = false;
  DateTime? _scheduledPublishDate;
  TimeOfDay? _scheduledPublishTime;

  bool _hasExpiry = false;
  DateTime? _expiryDate;
  TimeOfDay? _expiryTime;

  XFile? _attachmentFile;
  String? _existingAttachmentUrl;
  bool _removeAttachment = false;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final n = widget.noticeToEdit;

    _titleController = TextEditingController(text: n?.title ?? '');
    _bodyController = TextEditingController(text: n?.body ?? '');
    _venueController = TextEditingController(text: n?.eventVenue ?? '');

    _category = n?.category ?? NoticeCategory.general;
    _targetType = n?.targetType ?? NoticeTargetType.all;
    _selectedBlockId = n?.targetBlockId;

    _isEvent = n?.isEvent ?? false;
    if (n != null && n.eventStartsAt != null) {
      final s = n.eventStartsAt!.toLocal();
      _eventDate = DateTime(s.year, s.month, s.day);
      _eventStartTime = TimeOfDay(hour: s.hour, minute: s.minute);
    }
    if (n != null && n.eventEndsAt != null) {
      final e = n.eventEndsAt!.toLocal();
      _eventEndTime = TimeOfDay(hour: e.hour, minute: e.minute);
    }

    _isPinned = n?.isPinned ?? false;
    _requiresAck = n?.requiresAcknowledgment ?? false;

    if (n != null && n.status == NoticeStatus.scheduled) {
      _scheduleForLater = true;
      final pub = n.publishAt.toLocal();
      _scheduledPublishDate = DateTime(pub.year, pub.month, pub.day);
      _scheduledPublishTime = TimeOfDay(hour: pub.hour, minute: pub.minute);
    }

    if (n != null && n.expiresAt != null) {
      _hasExpiry = true;
      final exp = n.expiresAt!.toLocal();
      _expiryDate = DateTime(exp.year, exp.month, exp.day);
      _expiryTime = TimeOfDay(hour: exp.hour, minute: exp.minute);
    }

    _existingAttachmentUrl = n?.attachmentUrl;

    _loadBlocks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _venueController.dispose();
    super.dispose();
  }

  Future<void> _loadBlocks() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return;

    try {
      final res = await Supabase.instance.client
          .from('blocks')
          .select('*')
          .eq('society_id', societyId)
          .order('name');
      final list = (res as List).cast<Map<String, dynamic>>().map(BlockInfo.fromMap).toList();
      if (mounted) {
        setState(() => _availableBlocks = list);
      }
    } catch (_) {}
  }

  Future<void> _pickAttachment() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );

    if (picked != null && mounted) {
      setState(() {
        _attachmentFile = picked;
        _removeAttachment = false;
      });
    }
  }

  void _onCategoryChanged(NoticeCategory cat) {
    setState(() {
      _category = cat;
      if (cat == NoticeCategory.event && !_isEvent) {
        _isEvent = true;
        _eventDate ??= DateTime.now().add(const Duration(days: 2));
        _eventStartTime ??= const TimeOfDay(hour: 18, minute: 0);
        _eventEndTime ??= const TimeOfDay(hour: 20, minute: 0);
        _autoSuggestExpiry();
      }
    });
  }

  void _onEventToggled(bool value) {
    setState(() {
      _isEvent = value;
      if (value) {
        _eventDate ??= DateTime.now().add(const Duration(days: 2));
        _eventStartTime ??= const TimeOfDay(hour: 18, minute: 0);
        _eventEndTime ??= const TimeOfDay(hour: 20, minute: 0);
        _autoSuggestExpiry();
      }
    });
  }

  void _autoSuggestExpiry() {
    if (_eventDate != null) {
      _hasExpiry = true;
      _expiryDate = _eventDate!.add(const Duration(days: 1));
      _expiryTime = const TimeOfDay(hour: 23, minute: 59);
    }
  }

  Future<void> _pickEventDate() async {
    final now = DateTime.now();
    final initial = _eventDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _eventDate = picked;
        _autoSuggestExpiry();
      });
    }
  }

  Future<void> _pickEventStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _eventStartTime ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _eventStartTime = picked);
    }
  }

  Future<void> _pickEventEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _eventEndTime ?? const TimeOfDay(hour: 20, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _eventEndTime = picked);
    }
  }

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledPublishDate ?? now.add(const Duration(hours: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null && mounted) {
      setState(() => _scheduledPublishDate = picked);
    }
  }

  Future<void> _pickScheduleTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledPublishTime ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      setState(() => _scheduledPublishTime = picked);
    }
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _expiryDate = picked);
    }
  }

  Future<void> _pickExpiryTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _expiryTime ?? const TimeOfDay(hour: 23, minute: 59),
    );
    if (picked != null && mounted) {
      setState(() => _expiryTime = picked);
    }
  }

  Future<void> _saveNotice({required bool asDraft}) async {
    if (!_formKey.currentState!.validate()) return;

    if (_isEvent) {
      if (_eventDate == null || _eventStartTime == null || _eventEndTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select event date, start time, and end time.')),
        );
        return;
      }
    }

    if (_targetType == NoticeTargetType.block && (_selectedBlockId == null || _selectedBlockId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a specific target block.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final societyId = AppSession.instance.societyId!;
      final isEditing = widget.noticeToEdit != null;

      // Calculate event dates
      DateTime? eventStarts;
      DateTime? eventEnds;
      if (_isEvent && _eventDate != null && _eventStartTime != null && _eventEndTime != null) {
        eventStarts = DateTime(
          _eventDate!.year,
          _eventDate!.month,
          _eventDate!.day,
          _eventStartTime!.hour,
          _eventStartTime!.minute,
        );
        eventEnds = DateTime(
          _eventDate!.year,
          _eventDate!.month,
          _eventDate!.day,
          _eventEndTime!.hour,
          _eventEndTime!.minute,
        );

        if (eventEnds.isBefore(eventStarts)) {
          // If end time is earlier than start time, assume next day
          eventEnds = eventEnds.add(const Duration(days: 1));
        }
      }

      // Calculate status and publish date
      NoticeStatus status;
      DateTime publishAt = DateTime.now();

      if (asDraft) {
        status = NoticeStatus.draft;
      } else if (_scheduleForLater && _scheduledPublishDate != null) {
        final time = _scheduledPublishTime ?? const TimeOfDay(hour: 9, minute: 0);
        publishAt = DateTime(
          _scheduledPublishDate!.year,
          _scheduledPublishDate!.month,
          _scheduledPublishDate!.day,
          time.hour,
          time.minute,
        );
        status = publishAt.isAfter(DateTime.now())
            ? NoticeStatus.scheduled
            : NoticeStatus.published;
      } else {
        status = NoticeStatus.published;
        publishAt = DateTime.now();
      }

      // Calculate expiry date
      DateTime? expiresAt;
      if (_hasExpiry && _expiryDate != null) {
        final time = _expiryTime ?? const TimeOfDay(hour: 23, minute: 59);
        expiresAt = DateTime(
          _expiryDate!.year,
          _expiryDate!.month,
          _expiryDate!.day,
          time.hour,
          time.minute,
        );
      }

      final noticeRecord = NoticeRecord(
        id: widget.noticeToEdit?.id ?? '',
        societyId: societyId,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        category: _category,
        attachmentUrl: _removeAttachment ? null : _existingAttachmentUrl,
        targetType: _targetType,
        targetBlockId: _targetType == NoticeTargetType.block ? _selectedBlockId : null,
        isEvent: _isEvent,
        eventStartsAt: eventStarts,
        eventEndsAt: eventEnds,
        eventVenue: _venueController.text.trim().isNotEmpty ? _venueController.text.trim() : null,
        isPinned: _isPinned,
        requiresAcknowledgment: _requiresAck,
        status: status,
        publishAt: publishAt,
        expiresAt: expiresAt,
        createdAt: widget.noticeToEdit?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (isEditing) {
        await NoticesService.instance.updateNotice(
          noticeRecord,
          newAttachmentFile: _attachmentFile,
          removeAttachment: _removeAttachment,
        );
      } else {
        await NoticesService.instance.createNotice(
          noticeRecord,
          attachmentFile: _attachmentFile,
        );
      }

      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              asDraft
                  ? 'Notice saved as draft.'
                  : (status == NoticeStatus.scheduled
                      ? 'Notice scheduled for publication.'
                      : 'Notice published successfully!'),
            ),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save notice: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final isEditing = widget.noticeToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Notice' : 'Post Notice',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              // Title Field
              TextFormField(
                controller: _titleController,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: 'Notice Title *',
                  hintText: 'e.g. Scheduled Water Tank Cleaning',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: p.card,
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a title for the notice.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Category Selector
              Text('Category', style: textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: NoticeCategory.values.map((cat) {
                  final isSelected = _category == cat;
                  final catColor = cat.color(p);
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cat.icon,
                          size: 16,
                          color: isSelected ? Colors.white : catColor,
                        ),
                        const SizedBox(width: 6),
                        Text(cat.label),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) => _onCategoryChanged(cat),
                    selectedColor: catColor,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : p.textPrimary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    backgroundColor: p.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? catColor : p.hairline,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Event Toggle Card
              Container(
                decoration: BoxDecoration(
                  color: _isEvent ? p.secondary.withValues(alpha: 0.08) : p.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _isEvent ? p.secondary.withValues(alpha: 0.4) : p.hairline,
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.celebration_outlined,
                          color: _isEvent ? p.secondary : p.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'This is an Event',
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Shows a prominent calendar banner and timing',
                                style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _isEvent,
                          activeColor: p.secondary,
                          onChanged: _onEventToggled,
                        ),
                      ],
                    ),
                    if (_isEvent) ...[
                      const Divider(height: 24),
                      // Date picker button
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.calendar_today_rounded, color: p.secondary),
                        title: const Text('Event Date'),
                        subtitle: Text(
                          _eventDate != null
                              ? DateFormat('EEEE, d MMMM yyyy').format(_eventDate!)
                              : 'Select date',
                          style: TextStyle(
                            color: _eventDate != null ? p.textPrimary : p.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _pickEventDate,
                      ),
                      const SizedBox(height: 4),
                      // Start and End time row
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickEventStartTime,
                              icon: const Icon(Icons.schedule_rounded, size: 16),
                              label: Text(
                                _eventStartTime != null
                                    ? 'Start: ${_eventStartTime!.format(context)}'
                                    : 'Start Time',
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickEventEndTime,
                              icon: const Icon(Icons.schedule_send_rounded, size: 16),
                              label: Text(
                                _eventEndTime != null
                                    ? 'End: ${_eventEndTime!.format(context)}'
                                    : 'End Time',
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Venue field
                      TextFormField(
                        controller: _venueController,
                        decoration: InputDecoration(
                          labelText: 'Event Venue (Optional)',
                          hintText: 'e.g. Community Hall / Clubhouse Lawn',
                          prefixIcon: const Icon(Icons.place_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                          fillColor: p.cardMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Body Field
              TextFormField(
                controller: _bodyController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Notice Details / Body *',
                  hintText: 'Enter complete announcement information...',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: p.card,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter the details of the notice.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),

              // Target Audience Selection
              Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.hairline),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target Audience',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<NoticeTargetType>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('All Society'),
                            value: NoticeTargetType.all,
                            groupValue: _targetType,
                            onChanged: (val) {
                              if (val != null) setState(() => _targetType = val);
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<NoticeTargetType>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Specific Block'),
                            value: NoticeTargetType.block,
                            groupValue: _targetType,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _targetType = val;
                                  if (_selectedBlockId == null && _availableBlocks.isNotEmpty) {
                                    _selectedBlockId = _availableBlocks.first.id;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_targetType == NoticeTargetType.block) ...[
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedBlockId,
                        decoration: InputDecoration(
                          labelText: 'Select Block',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: p.cardMuted,
                        ),
                        items: _availableBlocks.map((b) {
                          return DropdownMenuItem(
                            value: b.id,
                            child: Text(b.name),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedBlockId = val),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Attachment Section
              Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.hairline),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.attachment_rounded, color: p.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Attachment (Optional)',
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_attachmentFile != null) ...[
                      Row(
                        children: [
                          Icon(Icons.image_outlined, color: p.secondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _attachmentFile!.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() => _attachmentFile = null),
                          ),
                        ],
                      ),
                    ] else if (_existingAttachmentUrl != null && !_removeAttachment) ...[
                      Row(
                        children: [
                          Icon(Icons.link_rounded, color: p.secondary),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Current attached file')),
                          TextButton(
                            onPressed: () => setState(() => _removeAttachment = true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: _pickAttachment,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Upload Photo or Flyer'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Options: Pin & Acknowledgment
              Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      secondary: Icon(Icons.push_pin_outlined, color: p.warning),
                      title: const Text('Pin notice to top'),
                      subtitle: const Text('Keeps notice prioritized above newer updates'),
                      value: _isPinned,
                      activeColor: p.warning,
                      onChanged: (val) => setState(() => _isPinned = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      secondary: Icon(Icons.assignment_turned_in_outlined, color: p.primary),
                      title: const Text('Require Resident Acknowledgment'),
                      subtitle: const Text('Residents must tap "I Understand" to confirm'),
                      value: _requiresAck,
                      activeColor: p.primary,
                      onChanged: (val) => setState(() => _requiresAck = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Scheduling & Expiry Settings
              Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.hairline),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Publication & Expiry Timing',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),

                    // Schedule publish toggle
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Schedule for later'),
                      subtitle: const Text('Notice goes live automatically at specified date/time'),
                      value: _scheduleForLater,
                      onChanged: (val) {
                        setState(() {
                          _scheduleForLater = val;
                          if (val) {
                            _scheduledPublishDate ??= DateTime.now().add(const Duration(hours: 4));
                            _scheduledPublishTime ??= TimeOfDay.now();
                          }
                        });
                      },
                    ),
                    if (_scheduleForLater) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickScheduleDate,
                              icon: const Icon(Icons.calendar_today_rounded, size: 15),
                              label: Text(
                                _scheduledPublishDate != null
                                    ? DateFormat('d MMM yyyy').format(_scheduledPublishDate!)
                                    : 'Pick Date',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickScheduleTime,
                              icon: const Icon(Icons.schedule_rounded, size: 15),
                              label: Text(
                                _scheduledPublishTime != null
                                    ? _scheduledPublishTime!.format(context)
                                    : 'Pick Time',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    const Divider(height: 16),

                    // Expiry toggle
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-expire notice'),
                      subtitle: const Text('Notice is moved to Expired after this time'),
                      value: _hasExpiry,
                      onChanged: (val) {
                        setState(() {
                          _hasExpiry = val;
                          if (val) {
                            _expiryDate ??= DateTime.now().add(const Duration(days: 7));
                            _expiryTime ??= const TimeOfDay(hour: 23, minute: 59);
                          }
                        });
                      },
                    ),
                    if (_hasExpiry) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickExpiryDate,
                              icon: const Icon(Icons.timer_outlined, size: 15),
                              label: Text(
                                _expiryDate != null
                                    ? DateFormat('d MMM yyyy').format(_expiryDate!)
                                    : 'Expiry Date',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickExpiryTime,
                              icon: const Icon(Icons.schedule_rounded, size: 15),
                              label: Text(
                                _expiryTime != null
                                    ? _expiryTime!.format(context)
                                    : 'Expiry Time',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => _saveNotice(asDraft: true),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Save as Draft'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : () => _saveNotice(asDraft: false),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isEditing
                                  ? 'Update Notice'
                                  : (_scheduleForLater ? 'Schedule Notice' : 'Publish Notice'),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
